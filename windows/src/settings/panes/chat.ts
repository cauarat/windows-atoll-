// Chat — the Mac's chatSection (SettingsView.swift): the "Anthropic API" group,
// then "ChatGPT (website)", which the Mac keeps last on purpose so nothing
// above it shifts. "Chat — other providers" and "Local models" come with the
// providers themselves (W-35, W-36).
//
// Phase 1 of the parity work draws the Mac's groups over today's behaviour:
// the model list is still the fixed one, the key keeps its Remove button (the
// owner kept it), and the ChatGPT group holds the one switch Windows has.
// The live model list with Custom…, and ChatGPT's master switch and Clear
// data, are W-34 and W-37.

import { Bridge } from "../../core/bridge";
import { t } from "../../core/i18n";
import {
  checkbox, divider, groupBox, hint, inlineRow, popup, pushButton, secureField,
  type PopupOption,
} from "../controls";
import { refreshSecret, save, secrets, setStatus, settings, subscribe } from "../store";

/** The Credential Manager key the chat reads. */
const API_KEY = "anthropic-api-key";

/**
 * Today's models. The Mac fills its popup from GET /v1/models and falls back
 * to a list of its own, with "Custom…" at the end — W-34. Names of products,
 * so they are not translated.
 */
const MODELS: { id: string; label: string }[] = [
  { id: "claude-opus-5", label: "Claude Opus 5" },
  { id: "claude-sonnet-5", label: "Claude Sonnet 5" },
  { id: "claude-haiku-4-5", label: "Claude Haiku 4.5" },
];

function modelOptions(): PopupOption[] {
  const options: PopupOption[] = MODELS.map((m) => ({ value: m.id, label: m.label }));
  // A model that is not on the list (an older build's default) stays on offer
  // under its id, rather than the popup quietly showing another one.
  if (!MODELS.some((m) => m.id === settings.model)) {
    options.push({ value: settings.model, label: settings.model });
  }
  return options;
}

/**
 * GroupBox "Anthropic API": the key, Save, a divider, the model, a hint —
 * VStack(spacing: 8) in the Mac's padding of 6.
 *
 * The key is written straight to the Credential Manager and never read back,
 * so the field stays empty and a stored key shows as "(stored)" in it: the
 * Windows stand-in for the Mac's field, which shows the key it holds.
 */
function anthropicGroup(): HTMLElement {
  const stored = () => secrets[API_KEY] === true;
  const placeholder = () => (stored() ? `••••••••••••  ${t("(stored)")}` : t("API key (sk-ant-…)"));

  const field = secureField("", () => {}, { placeholder: placeholder(), ariaLabel: t("API key") });

  const saveButton = pushButton(t("Save"), () => void saveKey(), { kind: "prominent" });
  // Windows only, kept by the owner: the Mac clears a key by saving an empty
  // field, which this window has never done.
  const removeButton = pushButton(t("Remove"), () => void removeKey());

  function paint() {
    field.placeholder = placeholder();
    removeButton.style.display = stored() ? "" : "none";
  }

  async function saveKey() {
    const value = field.value.trim();
    // An empty field saves nothing; Remove is what takes a key away.
    if (!value) return;
    try {
      await Bridge.secretSet(API_KEY, value);
      field.value = "";
      setStatus(t("✓ Key saved."));
      // Through the store, so the pane drawn next time starts from the truth.
      await refreshSecret(API_KEY);
      paint();
    } catch (err) {
      setStatus(`❌ ${t("Could not save: %@", String(err))}`);
    }
  }

  async function removeKey() {
    try {
      await Bridge.secretClear(API_KEY);
      setStatus(t("Key removed."));
      await refreshSecret(API_KEY);
      paint();
    } catch (err) {
      setStatus(`❌ ${t("Could not remove: %@", String(err))}`);
    }
  }

  const model = popup(modelOptions(), settings.model, (id) => {
    settings.model = id;
    void save();
  }, { label: t("Model") });

  // Divider().padding(.vertical, 2), inside the group's spacing of 8.
  const rule = divider();
  rule.style.margin = "2px 0";

  paint();
  return groupBox({ title: t("Anthropic API"), gap: 8 },
    field,
    inlineRow(saveButton, removeButton),
    rule,
    model,
    hint(t("Used by the chat. The list comes from your Anthropic account.")),
  );
}

/**
 * GroupBox "ChatGPT (website)": whether the chat tab opens ChatGPT's own page
 * rather than the chat built into the island. The Mac puts "Show ChatGPT in
 * the notch" above it, which this one then depends on, and "Clear ChatGPT
 * data" under the hint — W-37.
 */
function chatGptGroup(): HTMLElement {
  const fromChatTab = checkbox(t("Open it from the chat tab"), settings.webChat, (on) => {
    settings.webChat = on;
    void save();
  });
  subscribe("settings", () => fromChatTab.set(settings.webChat));

  const group = groupBox({ title: t("ChatGPT (website)"), gap: 8 },
    fromChatTab,
    hint(t("Opens chatgpt.com itself inside the island, with no API key. Signing in "
      + "is optional and only buys you history and memory. Attaching a window "
      + "or asking about a dropped file still uses the built-in chat.")),
  );
  // `.padding(.vertical, 4)` where the group above has `.padding(6)`: the
  // GroupBox's own 4 at the sides, 4 + 4 above and below.
  group.box.style.padding = "8px 4px";
  return group;
}

/** The Chat pane. */
export function render(): Node[] {
  return [anthropicGroup(), chatGptGroup()];
}
