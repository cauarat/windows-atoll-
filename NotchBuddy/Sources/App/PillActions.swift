import AppKit
import SwiftUI

/// Opening what a pill stands for.
///
/// There are two ways to ask now — the arrow on Home's card and a button on the
/// island's edge — so there is one place that answers. Keyed by pill id rather
/// than by `AgentTask`, because a button can be configured for a pill that has
/// no task at all: `AppState.setFocus` is guarded on `tasks` and so did nothing
/// at all for exactly those.
/// The last pill clicked and when, so a second click can be told apart from a
/// first. `PillOpen.opensTarget` is the rule; this is only the memory.
@MainActor private var lastPillClick: (id: String, at: Date)?

/// A double click landed on the island, but not on the pill's own button.
///
/// Opening a view resizes the island, and the ring hugs it — the bottom
/// buttons move by the whole height change — so the disc can slide out from
/// under a cursor that never moved, and the second click lands on the island
/// instead. macOS decides a double click from where the *pointer* is and how
/// long it waited, and does not care what moved underneath, so the window
/// controller's own click monitor still sees `clickCount == 2`. It calls this.
///
/// The memory is cleared either way, so the button's own path and this one
/// cannot both open the same thing.
@MainActor
func pillDoubleClickedOnIsland() {
    guard let last = lastPillClick,
          PillOpen.opensTarget(pill: last.id, lastPill: last.id,
                               lastClick: last.at, now: Date())
    else { return }
    lastPillClick = nil
    openPillTarget(last.id)
}

@MainActor
func openPill(_ id: String) {
    let state = AppState.shared
    // A click opens the island; clicking the same pill again opens the service
    // behind it. Read before the memory is updated, and acted on at the end:
    // the island half runs either way, so a double click is "the island, then
    // the service" rather than a different thing altogether.
    let alsoOpenTarget = PillOpen.opensTarget(pill: id,
                                              lastPill: lastPillClick?.id,
                                              lastClick: lastPillClick?.at,
                                              now: Date())
    // Cleared when it fires, so `pillDoubleClickedOnIsland` cannot open the
    // same thing a second time off the same pair of clicks.
    lastPillClick = alsoOpenTarget ? nil : (id, Date())
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
        if alsoOpenTarget { openPillTarget(id) }
        return
    }
    // Every pill lands somewhere, not just the message ones. Focus used to
    // move here while `state.view` stayed where it was, which left the island
    // showing one pill's card wearing another pill's face — and, for Now
    // Playing, no way to reach the player at all: the click activated the
    // source app and the island never changed. Home is where a focused pill
    // shows itself, and `homeShowsPlayer` turns that into the player.
    state.view = .overview
    // Only on the second click. One click asking for the player and getting
    // the browser on top of it is what this used to do, and the island is
    // where the controls are.
    if alsoOpenTarget { openPillTarget(id) }
}

/// That bundle identifier, but only when it resolves to something installed.
///
/// Lives here rather than on `PillOpen` so that stays free of AppKit: the
/// decision is tested on its own, and this is the one fact from the machine
/// that it needs handed to it.
func installedBundleID(_ bundleID: String) -> String? {
    guard !bundleID.isEmpty, bundleID != PillOpen.websiteSetting else { return nil }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        ? bundleID : nil
}

/// Bring an application up, launching it if it is not already running. The
/// shape `MusicController.openMusic()` uses.
@MainActor
private func activate(bundleID: String) {
    if let running = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundleID }) {
        running.activate(options: .activateIgnoringOtherApps)
        return
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Open a message service the way the user actually reaches it.
@MainActor
private func openMessageService(setting: String, serverURL: URL?) {
    switch PillOpen.target(setting: setting,
                           installedBundleID: installedBundleID(setting),
                           serverURL: serverURL) {
    case .application(let bundleID): activate(bundleID: bundleID)
    case .website(let url):          NSWorkspace.shared.open(url)
    case .nothing:                   break
    }
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
        // The tab that is playing, not merely the browser holding it: being
        // dropped into whatever tab happened to be frontmost is being sent
        // somewhere you did not ask for.
        MusicController.shared.openNowPlayingTab()
        #endif
    case "integration_mattermost":
        #if !APPSTORE
        openMessageService(setting: MattermostSettings.openTarget,
                           serverURL: MattermostClient.normalizedBaseURL(MattermostSettings.serverURL))
        #endif
    case "integration_clickmassa":
        #if !APPSTORE
        openMessageService(setting: ClickMassaSettings.openTarget,
                           serverURL: ClickMassaClient.normalizedAppURL(ClickMassaSettings.serverURL))
        #endif
    default:
        break
    }
}
