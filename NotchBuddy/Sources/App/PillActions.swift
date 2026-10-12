import AppKit
import SwiftUI

/// Opening what a pill stands for.
///
/// There are two ways to ask now — the arrow on Home's card and a button on the
/// island's edge — so there is one place that answers. Keyed by pill id rather
/// than by `AgentTask`, because a button can be configured for a pill that has
/// no task at all: `AppState.setFocus` is guarded on `tasks` and so did nothing
/// at all for exactly those.
@MainActor
func openPill(_ id: String) {
    let state = AppState.shared
    // Focus only what is actually loaded. Pointing `focusId` at a task that is
    // not there makes the focused card fall back to the first task, and Home
    // would then show something other than what was clicked.
    if state.tasks.contains(where: { $0.id == id }) {
        state.setFocus(id)
    }
    SoundEngine.shared.play("blip")
    // A message pill opens everything still waiting from that service. Every
    // other pill stands for somewhere else -- an app, a dashboard -- but this
    // one stands for conversations the island is already holding, and the reply
    // is written on the card a row opens, so sending it to a browser would be
    // sending it away from the answer.
    //
    // The list rather than the newest one: pointing at a single message means
    // the other four that came in are reachable only by answering past them.
    // The notifications pill stands for both services at once, so it opens
    // the one queue rather than picking a service to be first.
    if id == PillCatalog.notificationsID {
        MessageInbox.shared.openAllSources()
        state.view = .messages
        NotificationCenter.default.post(name: .showMessageCard, object: nil)
        return
    }
    if let source = MessageSource.allCases.first(where: { $0.pillID == id }) {
        MessageInbox.shared.openList(source)
        state.view = .messages
        NotificationCenter.default.post(name: .showMessageCard, object: nil)
        return
    }
    openPillTarget(id)
}

/// The app, site or provider behind a pill.
@MainActor
func openPillTarget(_ id: String) {
    switch id {

    case "integration_claude":
        let vscodeBundleId = "com.microsoft.VSCode"
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
            app.activate(options: .activateIgnoringOtherApps)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
        }
    case "integration_resend":
        NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
    case "integration_vercel":
        NSWorkspace.shared.open(URL(string: "https://vercel.com/dashboard")!)
    case "integration_github":
        NSWorkspace.shared.open(URL(string: "https://github.com")!)
    case "integration_n8n":
        if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    case "integration_stripe":
        NSWorkspace.shared.open(URL(string: "https://dashboard.stripe.com/payments")!)
    case "integration_notion":
        NSWorkspace.shared.open(URL(string: "https://notion.so")!)
    case "integration_calcom":
        NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
    case "agent_cursor":
        #if !APPSTORE
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
        #endif
    case "agent_codex":
        #if !APPSTORE
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
        #endif
    case "agent_gemini", "agent_antigravity":
        #if !APPSTORE
        let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                 "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
        if let hit = terminalBundleIds.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            hit.activate(options: .activateIgnoringOtherApps)
        }
        #endif
    case "ai_anthropic":
        switchChatProvider(.anthropic)
    case "ai_google":
        switchChatProvider(.google)
    case "ai_openai":
        switchChatProvider(.openai)
    case "ai_ollama":
        switchChatProvider(.ollama)
    case "ai_lmstudio":
        switchChatProvider(.lmstudio)
    case "integration_music":
        #if !APPSTORE
        MusicController.shared.openMusic()
        #endif
    default:
        break
    }
}
