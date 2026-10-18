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
    // Every pill lands somewhere, not just the message ones. Focus used to
    // move here while `state.view` stayed where it was, which left the island
    // showing one pill's card wearing another pill's face — and, for Now
    // Playing, no way to reach the player at all: the click activated the
    // source app and the island never changed. Home is where a focused pill
    // shows itself, and `homeShowsPlayer` turns that into the player.
    state.view = .overview
    openPillTarget(id)
}

/// The app, site or provider behind a pill.
@MainActor
func openPillTarget(_ id: String) {
    switch id {

    case "integration_claude":
        // Whatever terminal is open: Claude Code runs in one, and this pill
        // has not meant Visual Studio Code for a long time.
        #if !APPSTORE
        let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                 "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
        if let hit = terminalBundleIds.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            hit.activate(options: .activateIgnoringOtherApps)
        }
        #endif
    case "integration_music":
        #if !APPSTORE
        MusicController.shared.openMusic()
        #endif
    default:
        break
    }
}
