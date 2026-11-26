// The real chat behind the phone link (chat.rs holds the rules): the Anthropic API, with the key in this
// computer's keystore, which never leaves it, and a conversation of the phone's own, in memory only — the
// island's chat is not touched. The twin of the Mac's PhoneLinkChatService.
//
// The models are the Mac's rule: the one chosen in Settings › Chat for each provider that is set up there. Windows
// and Linux have one provider so far, Anthropic, so the phone is offered its model while a key is stored, and
// nothing otherwise. Answers come all at once, as on the Mac.
//
// Failures are sorted into a few kinds here and only the kind goes on: a provider's message may contain part of a
// key, so it is neither forwarded nor logged.

use std::sync::{Arc, Mutex};

use serde_json::{json, Value};
use tauri::{AppHandle, Manager};
use tokio::sync::mpsc::UnboundedSender;

use super::chat::{BoxFuture, ChatBackend, ChatConfig, ChatFail, ModelOption};
use crate::{claude, log, secrets, Shared};

const ANTHROPIC: &str = "anthropic";
/// The keystore entry Settings › Chat writes (panes/chat.ts) and the island's chat reads.
const KEY: &str = "anthropic-api-key";
/// Turns kept for the phone (user + assistant), oldest dropped first — the Mac's `maxTurns`.
const MAX_TURNS: usize = 20;
const MAX_TOKENS: u32 = 2048;
const MAX_MODEL_CHARS: usize = 200;

pub struct AppChat {
    app: AppHandle,
    /// `{role, content}` with plain text, as the Mac keeps it.
    history: Arc<Mutex<Vec<Value>>>,
}

impl AppChat {
    pub fn new(app: AppHandle) -> Self {
        Self { app, history: Arc::new(Mutex::new(Vec::new())) }
    }

    /// The switch, the island chat's model and the name Mochi calls the user, read again for every message.
    fn read(&self) -> (bool, String, String) {
        let shared = self.app.state::<Shared>();
        let s = shared.settings.lock().unwrap();
        (s.phone_chat, s.model.clone(), s.user_name.clone())
    }
}

impl ChatBackend for AppChat {
    fn config(&self) -> ChatConfig {
        let (enabled, model, _) = self.read();
        ChatConfig { enabled, allowed: models(&model, secrets::present(KEY)) }
    }

    fn send(&self, model_id: &str, text: String, _deltas: UnboundedSender<String>) -> BoxFuture<Result<String, ChatFail>> {
        let (_, _, name) = self.read();
        let history = self.history.clone();
        let id = model_id.to_string();
        Box::pin(async move {
            let Some(model) = parse_model_id(&id) else { return Err(ChatFail::Internal) };
            let Some(key) = secrets::get(KEY) else { return Err(ChatFail::NoKey) };
            let messages = {
                let mut h = history.lock().unwrap();
                h.push(json!({ "role": "user", "content": text }));
                let drop = h.len().saturating_sub(MAX_TURNS);
                h.drain(..drop);
                // The API wants the conversation to open with the user.
                while h.first().is_some_and(|m| m["role"] != "user") {
                    h.remove(0);
                }
                h.clone()
            };
            let forget_question = || {
                // The question goes too, so the next one is not asked twice.
                let mut h = history.lock().unwrap();
                if h.last().is_some_and(|m| m["role"] == "user") {
                    h.pop();
                }
            };
            match claude::call(&key, &request(model, &system_prompt(&name), &messages)).await {
                Ok(response) => match answer_text(&response) {
                    Some(answer) => {
                        history.lock().unwrap().push(json!({ "role": "assistant", "content": answer }));
                        Ok(answer)
                    }
                    None => {
                        forget_question();
                        Err(ChatFail::Provider)
                    }
                },
                Err(err) => {
                    forget_question();
                    let kind = classify(&err);
                    // The kind only: the text may echo a key.
                    log::line(format!("phone link: chat failed ({kind:?})"));
                    Err(kind)
                }
            }
        })
    }

    fn reset(&self) {
        self.history.lock().unwrap().clear();
    }
}

// ── Pure helpers (tested below) ───────────────────────────────────────────────

/// What the phone may pick: the island chat's model, while a key is stored.
fn models(model: &str, has_key: bool) -> Vec<ModelOption> {
    let model = model.trim();
    if !has_key || model.is_empty() {
        return Vec::new();
    }
    let id = format!("{ANTHROPIC}/{model}");
    if parse_model_id(&id).is_none() {
        return Vec::new();
    }
    vec![ModelOption { label: format!("Anthropic · {model}"), provider: ANTHROPIC.into(), id }]
}

/// "anthropic/model" with a plain model name.
fn parse_model_id(id: &str) -> Option<&str> {
    let model = id.strip_prefix("anthropic/")?.trim();
    (!model.is_empty() && model.chars().count() <= MAX_MODEL_CHARS && !model.chars().any(char::is_control)).then_some(model)
}

/// The Mac's phone prompt (PhoneLinkChatService.prepare): the screen is small, light Markdown is welcome.
fn system_prompt(name: &str) -> String {
    let opening = match name.trim() {
        "" => "You are Mochi, a personal AI assistant, answering on the user's phone through Notchy.".to_string(),
        name => format!("You are Mochi, {name}'s personal AI assistant, answering on their phone through Notchy."),
    };
    format!(
        "{opening} Respond in the user's language. Be helpful and concise: the screen is small. \
Use light Markdown when it helps: short paragraphs, bullet lists, **bold**, `inline code`. Avoid tables and big headings."
    )
}

/// The request, with web search as the island's chat has it (claude.rs), and fewer searches: a phone waits.
fn request(model: &str, system: &str, messages: &[Value]) -> Value {
    json!({
        "model": model,
        "max_tokens": MAX_TOKENS,
        "system": system,
        "messages": messages,
        "tools": [{ "type": "web_search_20260209", "name": "web_search", "max_uses": 3 }],
        "fallbacks": "default",
    })
}

/// Every text block, in order: with web search the answer comes in several, between the searches. None when there is
/// nothing to say (a refusal has no text).
fn answer_text(response: &Value) -> Option<String> {
    let text: String = response["content"]
        .as_array()?
        .iter()
        .filter(|b| b["type"] == "text")
        .filter_map(|b| b["text"].as_str())
        .collect();
    let text = text.trim();
    (!text.is_empty()).then(|| text.to_string())
}

/// Which kind of failure an error from `claude::call` stands for, by what does not change with its wording: an
/// HTTP status, or the network error it starts with.
fn classify(err: &str) -> ChatFail {
    let has = |code: &str| err.split(|c: char| !c.is_ascii_digit()).any(|w| w == code);
    if has("401") || has("403") {
        return ChatFail::Auth;
    }
    if err.starts_with("Network error") {
        return ChatFail::Unreachable;
    }
    ChatFail::Provider
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_phone_is_offered_the_island_chats_model_only_while_a_key_is_stored() {
        assert_eq!(
            models("claude-opus-5", true),
            vec![ModelOption { id: "anthropic/claude-opus-5".into(), provider: "anthropic".into(), label: "Anthropic · claude-opus-5".into() }]
        );
        assert!(models("claude-opus-5", false).is_empty(), "no key: nothing to offer");
        assert!(models("  ", true).is_empty());
        assert!(models("a\nb", true).is_empty());
    }

    #[test]
    fn model_ids_name_anthropic_and_a_plain_model() {
        assert_eq!(parse_model_id("anthropic/claude-opus-5"), Some("claude-opus-5"));
        for bad in ["", "anthropic", "anthropic/", "anthropic/ ", "openai/gpt", "Anthropic/x", "anthropic/a\nb", &format!("anthropic/{}", "x".repeat(201))] {
            assert_eq!(parse_model_id(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn the_prompt_is_the_macs_and_names_the_user_only_when_there_is_a_name() {
        let plain = system_prompt("  ");
        assert!(plain.starts_with("You are Mochi, a personal AI assistant, answering on the user's phone through Notchy. Respond"));
        assert!(plain.ends_with("Avoid tables and big headings."));
        assert!(system_prompt(" João ").starts_with("You are Mochi, João's personal AI assistant, answering on their phone through Notchy."));
    }

    #[test]
    fn the_answer_is_every_text_block_in_order() {
        let r = json!({ "content": [
            { "type": "text", "text": "Looking. " },
            { "type": "server_tool_use", "name": "web_search" },
            { "type": "web_search_tool_result", "content": [] },
            { "type": "text", "text": "Found it.\n" },
        ]});
        assert_eq!(answer_text(&r).as_deref(), Some("Looking. Found it."));
        assert_eq!(answer_text(&json!({ "content": [], "stop_reason": "refusal" })), None);
        assert_eq!(answer_text(&json!({})), None);
    }

    #[test]
    fn failures_are_sorted_by_status_and_never_by_wording() {
        assert_eq!(classify("Claude API 401 Unauthorized: invalid x-api-key"), ChatFail::Auth);
        assert_eq!(classify("Claude API 403 Forbidden: nope"), ChatFail::Auth);
        assert_eq!(classify("Claude API 429 Too Many Requests: slow down"), ChatFail::Provider);
        assert_eq!(classify("Claude API 500 Internal Server Error: boom"), ChatFail::Provider);
        assert_eq!(classify("Network error: connection refused"), ChatFail::Unreachable);
        assert_eq!(classify("Bad API response: eof"), ChatFail::Provider);
        // 4010 or 14012 are not 401
        assert_eq!(classify("something 14012 happened"), ChatFail::Provider);
    }

    #[test]
    fn the_request_carries_the_conversation_and_nothing_of_the_island() {
        let body = request("claude-opus-5", "sys", &[json!({ "role": "user", "content": "hi" })]);
        assert_eq!(body["model"], "claude-opus-5");
        assert_eq!(body["max_tokens"], MAX_TOKENS);
        assert_eq!(body["messages"], json!([{ "role": "user", "content": "hi" }]));
        assert_eq!(body["tools"][0]["max_uses"], 3);
    }
}
