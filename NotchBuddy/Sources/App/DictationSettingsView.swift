import AVFoundation
import SwiftUI

/// Dictation's settings: on or off, where the transcription service is, the
/// key held to talk, and what becomes of the text.
struct DictationSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var dictation = DictationController.shared
    @State private var trusted = RadialChordTap.isTrusted
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var address = ""

    /// Run from the Notchy source folder; dictation-service/README.md has the rest.
    static let startCommand = "cd dictation-service && ./scripts/start.sh"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use dictation", isOn: $state.dictationEnabled)
                    caption(Text(loc: "Hold a key in any app, speak, and let go: the text is typed where the "
                                 + "cursor is. Or open Dictation from the menu bar and use its Record button."))
                    caption(Text(loc: "The speech model runs on your own computer, in Notchy's transcription "
                                 + "service. The audio goes only to the address below, and is never saved."))
                    if state.dictationEnabled {
                        microphoneRow
                        accessibilityRow
                    }
                }
                .padding(6)
            }

            GroupBox("Transcription service") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Address").frame(width: 70, alignment: .leading)
                        TextField(DictationProtocol.defaultServiceURL, text: $address)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitAddress() }
                        Button("Test connection") {
                            commitAddress()
                            Task { await dictation.refreshService() }
                        }
                    }
                    serviceRow
                    HStack(spacing: 8) {
                        Text("Language").frame(width: 70, alignment: .leading)
                        Text(verbatim: "\(DictationProtocol.languageLabel) · \(DictationProtocol.language)")
                    }
                    caption(Text("To start it on this computer, from the Notchy source folder:"))
                    HStack(spacing: 8) {
                        Text(verbatim: Self.startCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") { DictationInserter.copy(Self.startCommand) }
                            .font(.system(size: 11))
                    }
                    caption(Text(loc: "The first start downloads the Qwen3-ASR-1.7B model (about 4.7 GB). Without "
                                 + "an NVIDIA GPU the text appears when you stop speaking; with one, while you "
                                 + "speak. dictation-service/README.md has the details."))
                }
                .padding(6)
            }

            GroupBox("Hold to talk") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Key", selection: $state.dictationHoldKey) {
                        ForEach(DictationHoldKey.allCases) { key in
                            Text(loc: key.title).tag(key.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 340)
                    if state.dictationHoldKey == DictationHoldKey.fn.rawValue {
                        HStack(spacing: 8) {
                            caption(Text(loc: "If 🌐 opens the emoji picker, set System Settings › Keyboard › "
                                         + "“Press 🌐 key to” to “Do Nothing”."))
                            Spacer()
                            Button("Keyboard Settings") { Self.openKeyboardSettings() }
                                .font(.system(size: 11))
                        }
                    }
                    caption(Text(loc: "A quick tap, or another key pressed while holding, does nothing — "
                                 + "shortcuts such as ⌥E keep working. Escape cancels."))
                }
                .padding(6)
            }

            GroupBox("When the text is ready") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("After dictating", selection: $state.dictationInsertMode) {
                        ForEach(DictationInsertMode.allCases) { mode in
                            Text(loc: mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 340)
                    caption(Text(loc: "Pasting puts the text on the clipboard for a moment, presses ⌘V for you, "
                                 + "and gives back what the clipboard held."))
                }
                .padding(6)
            }
        }
        .onAppear {
            address = state.dictationServiceURL
            refreshPermissions()
            Task { await dictation.refreshService() }
        }
        .onChange(of: state.dictationEnabled) { _, on in
            // Asked when the feature is turned on, not at launch: macOS shows
            // these prompts once per app.
            guard on else { return }
            trusted = RadialChordTap.requestTrust()
            Task {
                _ = await VoiceRecorder.hasMicrophonePermission()
                refreshPermissions()
            }
        }
    }

    // MARK: Rows

    @ViewBuilder private var microphoneRow: some View {
        let ok = microphone == .authorized
        HStack(spacing: 8) {
            dot(ok)
            caption(ok ? Text("Microphone allowed.") : Text("Notchy needs the microphone to hear you."))
            Spacer()
            if !ok {
                if microphone == .notDetermined {
                    Button("Allow") {
                        Task {
                            _ = await VoiceRecorder.hasMicrophonePermission()
                            refreshPermissions()
                        }
                    }
                    .font(.system(size: 11))
                } else if let url = VoiceRecorder.microphoneSettingsURL {
                    Button("Open Settings") { NSWorkspace.shared.open(url) }
                        .font(.system(size: 11))
                }
            }
        }
    }

    @ViewBuilder private var accessibilityRow: some View {
        let ok = trusted && !state.dictationTapFailed
        HStack(spacing: 8) {
            dot(ok)
            caption(ok ? Text("Accessibility granted.")
                       : Text("Notchy needs Accessibility to hear the key you hold and to paste the text."))
            Spacer()
            if !ok {
                Button("Open Settings") { RadialChordTap.openAccessibilitySettings() }
                    .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder private var serviceRow: some View {
        HStack(spacing: 8) {
            switch dictation.serviceStatus {
            case .ready(let health):
                dot(true)
                caption(Text(verbatim: health.info.streaming
                             ? L("Connected — \(health.info.modelName), \(health.info.backend) on \(health.info.device): text while you speak.")
                             : L("Connected — \(health.info.modelName), \(health.info.backend) on \(health.info.device): text when you stop.")))
            case .loading(let health):
                dot(nil)
                caption(Text(verbatim: L("The service is loading \(health.info.modelName)…")))
            case .broken(let health):
                dot(false)
                caption(Text(verbatim: L("The service cannot run the model: \(health.error ?? "")")))
            case .offline:
                dot(false)
                caption(Text(verbatim: L("Nothing is answering at \(state.dictationServiceURL). Start the service, then test again.")))
            case .invalidAddress:
                dot(false)
                caption(Text("That is not a valid address."))
            case .notTheService:
                dot(false)
                caption(Text("Something answered, but it is not Notchy's transcription service."))
            case .checking:
                ProgressView().controlSize(.small)
                caption(Text("Checking…"))
            case .unknown:
                EmptyView()
            }
            Spacer()
        }
    }

    // MARK: Helpers

    private func caption(_ text: Text) -> some View {
        text.font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Green, red, or amber for "not yet".
    private func dot(_ ok: Bool?) -> some View {
        Circle()
            .fill(Color(hex: ok == true ? "#34D399" : ok == false ? "#F4505E" : "#F5A524"))
            .frame(width: 8, height: 8)
    }

    private func commitAddress() {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        state.dictationServiceURL = typed.isEmpty ? DictationProtocol.defaultServiceURL : typed
        address = state.dictationServiceURL
    }

    private func refreshPermissions() {
        trusted = RadialChordTap.isTrusted
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
