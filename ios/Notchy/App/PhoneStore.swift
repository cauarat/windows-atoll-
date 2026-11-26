import SwiftUI
import UIKit

// MARK: - Everything the phone knows, and everything it can do
//
// One store for the app, on the main actor: the computer it is paired with, the state of the link,
// what the computer offers (the chat), and the few things the phone can send back.

@MainActor
final class PhoneStore: ObservableObject {
    static let shared = PhoneStore()

    @Published private(set) var computer: PairedComputer?
    @Published private(set) var status: LinkClient.Status = .idle
    @Published private(set) var caps: Set<String> = []
    /// A link scanned or opened from outside, waiting for the user to confirm it.
    @Published var pendingPairing: PairedComputer?
    /// A short line shown under the island for a few seconds.
    @Published var toast: String?

    // Chat.
    @Published private(set) var chatModels: [ChatModel] = []
    @Published var chatModelId: String?
    @Published private(set) var chat: [ChatEntry] = []
    @Published private(set) var chatRunningId: String?

    struct ChatEntry: Identifiable, Equatable {
        enum Role { case user, assistant, error }
        let id: String
        var role: Role
        var text: String
    }

    private let client: LinkClient
    private var toastItem: DispatchWorkItem?

    private init() {
        client = LinkClient(deviceName: UIDevice.current.name)
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }
        client.onStatus = { [weak self] status in
            Task { @MainActor in self?.statusChanged(status) }
        }
        client.onMoved = { moved in
            Task { @MainActor in
                PairingStore.save(moved)
                PhoneStore.shared.computer = moved
            }
        }
        computer = PairingStore.load()
        if let computer { client.start(computer) }
    }

    // MARK: Pairing

    /// A `notchy://pair` link from the camera, a scan or the clipboard: shown for confirmation, never paired silently.
    func offer(link: String) -> Bool {
        guard let parsed = PairingLink.parse(link) else { return false }
        pendingPairing = parsed
        return true
    }

    func handle(url: URL) {
        if !offer(link: url.absoluteString) {
            show(String(localized: "That link is not a Notchy pairing link."))
        }
    }

    func confirmPairing() {
        guard let new = pendingPairing else { return }
        pendingPairing = nil
        client.stop()
        resetPicture()
        PairingStore.save(new)
        computer = new
        client.start(new)
    }

    func unpair() {
        client.stop()
        PairingStore.clear()
        computer = nil
        resetPicture()
    }

    func retry() { client.retryNow() }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var computerName: String {
        if case .connected(let desktop, _) = status, !desktop.isEmpty { return desktop }
        return computer?.name ?? ""
    }

    // MARK: Scene

    func scenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            client.retryNow()
        case .background:
            // iOS gives an app a little time before it is suspended; the link stays up for it, so an
            // answer still arriving when the phone is put away is there when Notchy is opened again.
            BackgroundGrace.begin()
        default:
            break
        }
    }

    // MARK: From the computer

    private func statusChanged(_ new: LinkClient.Status) {
        status = new
        switch new {
        case .connected:
            break
        case .unauthorized:
            caps = []
            show(String(localized: "Your computer no longer knows this phone. Pair again from its Settings."))
        default:
            caps = []
        }
    }

    private func receive(_ message: ServerMessage) {
        #if DEBUG
        defer { DemoSeed.observe(message) }
        #endif
        switch message {
        case .welcome(_, _, _, let offered):
            caps = offered
            if offered.contains("chat") { client.send(["type": "chatModels"]) }
        case .chatModels(let models):
            chatModels = models
            if chatModelId == nil || !models.contains(where: { $0.id == chatModelId }) { chatModelId = models.first?.id }
        case .chatDelta(let id, let text):
            if let i = chat.firstIndex(where: { $0.id == id }) {
                chat[i].text += text
            } else {
                chat.append(ChatEntry(id: id, role: .assistant, text: text))
            }
        case .chatDone(let id, let text):
            if let text {
                if let i = chat.firstIndex(where: { $0.id == id }) { chat[i].text = text }
                else { chat.append(ChatEntry(id: id, role: .assistant, text: text)) }
            }
            if chatRunningId == id { chatRunningId = nil }
            SoundEngine.shared.play("pop")
        case .chatError(let id, let reason, let message):
            if chatRunningId == id { chatRunningId = nil }
            guard reason != "canceled" else { return }
            chat.append(ChatEntry(id: id + "-error", role: .error, text: Self.chatErrorText(reason) ?? message))
        case .error, .pong, .other:
            break
        }
    }

    private func resetPicture() {
        caps = []
        chat = []
        chatModels = []
        chatRunningId = nil
        status = .idle
    }

    // MARK: Chat

    var canChat: Bool { caps.contains("chat") && !chatModels.isEmpty }

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, chatRunningId == nil, let model = chatModelId else { return }
        let id = "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
        chat.append(ChatEntry(id: id + "-q", role: .user, text: trimmed))
        chatRunningId = id
        client.send(["type": "chatSend", "id": id, "model": model, "text": String(trimmed.prefix(4000))])
        SoundEngine.shared.play("send")
    }

    func cancelChat() {
        guard let id = chatRunningId else { return }
        client.send(["type": "chatCancel", "id": id])
        chatRunningId = nil
    }

    func newChat() {
        client.send(["type": "chatReset"])
        chat = []
        chatRunningId = nil
    }

    static func chatErrorText(_ reason: String) -> String? {
        switch reason {
        case "busy": return String(localized: "Mochi is still answering the last message.")
        case "rate": return String(localized: "That's a lot of messages. Try again in a few minutes.")
        case "too_long": return String(localized: "That message is too long.")
        case "no_key": return String(localized: "That provider is not set up on your computer.")
        case "unreachable": return String(localized: "Your computer could not reach the provider.")
        case "auth": return String(localized: "The provider refused the key saved on your computer.")
        case "off", "not_allowed": return String(localized: "Chat from the phone is turned off on your computer.")
        default: return nil
        }
    }

    // MARK: Toast

    func show(_ text: String) {
        toastItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = text }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil } }
        }
        toastItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: item)
    }
}

// MARK: - A little time after the app leaves the front

@MainActor
enum BackgroundGrace {
    private static var task: UIBackgroundTaskIdentifier = .invalid

    static func begin() {
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "Notchy link") {
            end()
        }
    }

    static func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

// MARK: - Screenshots without a computer (Debug builds only)

#if DEBUG
/// `NOTCHY_DEMO=home|chat` fills the store with a made-up picture, for looking at the screens in the
/// simulator: a connected computer, and with `chat` a short conversation. Never in a Release build;
/// nothing of it is sent anywhere.
enum DemoSeed {
    @MainActor static func applyIfAsked() {
        let env = ProcessInfo.processInfo.environment
        // `NOTCHY_PAIR_LINK=<notchy://pair…>` pairs at launch, without the confirmation (the simulator's
        // "Open in Notchy?" and the app's own alert both need a tap nobody can script).
        if let link = env["NOTCHY_PAIR_LINK"], PhoneStore.shared.offer(link: link) {
            PhoneStore.shared.confirmPairing()
        }
        guard let mode = env["NOTCHY_DEMO"] else { return }
        PhoneStore.shared.debugSeed(mode)
    }

    /// `NOTCHY_AUTO=chat`: sends a chat message a moment after the computer welcomes the phone, so a
    /// round trip with a computer can run unattended.
    @MainActor static func observe(_ message: ServerMessage) {
        let auto = Set((ProcessInfo.processInfo.environment["NOTCHY_AUTO"] ?? "").split(separator: ",").map(String.init))
        guard !auto.isEmpty else { return }
        let store = PhoneStore.shared
        switch message {
        case .welcome where auto.contains("chat"):
            after(3) { store.sendChat("Hello from the phone") }
        default:
            break
        }
    }

    @MainActor private static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}

extension PhoneStore {
    func debugSeed(_ mode: String) {
        computer = PairedComputer(host: "192.168.1.20", port: 47830, fingerprint: String(repeating: "a", count: 64),
                                  token: String(repeating: "x", count: 32), name: "MacBook Pro")
        status = .connected(desktop: "MacBook Pro", os: "macos")
        caps = ["chat"]
        if mode == "chat" {
            chatModels = [ChatModel(id: "anthropic/claude-sonnet-5-5", provider: "anthropic", label: "Anthropic · claude-sonnet-5-5")]
            chatModelId = chatModels.first?.id
            chat = [
                ChatEntry(id: "1-q", role: .user, text: "Three names for a cat who sleeps all day?"),
                ChatEntry(id: "1", role: .assistant, text: "Here are three, from **sleepiest** up:\n\n- `Nap`\n- Cushion\n- Sir Snooze"),
            ]
        }
    }
}
#endif
