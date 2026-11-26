import SwiftUI

/// The dictation card: what is being heard, then the text to edit, copy or
/// paste.
///
/// Built like the other notification cards — the 108 pt gutter for Mochi, a
/// who line, the body, a row of buttons — in hydration's 240 rather than 160,
/// because a dictation is a few lines and the editor needs them. The big red
/// button records and stops.
///
/// The island builds every view whenever it opens, so nothing here moves
/// unless this card is the one on screen: the timer and the meter are drawn
/// only while it shows and is recording.
struct DictationCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var dictation = DictationController.shared
    @FocusState private var editing: Bool

    private var onScreen: Bool { state.view == .dictation && state.mode == .expanded }

    var body: some View {
        ZStack {
            CardBackground(wash: wash)
            VStack(alignment: .leading, spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
                controls
                    .padding(.top, 8)
            }
            .padding(.leading, IslandConst.lead(108, flush: 18, hidden: state.hideCharacters))
            .padding(.trailing, 18)
            .padding(.vertical, 12)
        }
        .onChange(of: editing) { _, isEditing in
            // The editor holds the card the way a half-written reply does.
            state.isReplying = isEditing
            state.isPinned = isEditing
        }
    }

    private var wash: CardBackground<EmptyView>.Wash? {
        switch dictation.phase {
        case .recording: return .pink
        case .failed: return .red
        case .done: return .soft
        default: return nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: dotColor)).frame(width: 7, height: 7)
            Text("Dictation").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            // The language the model is asked for, named the way the service
            // names it: it is not a sentence to translate.
            Text(verbatim: "\(DictationProtocol.languageLabel) · \(DictationProtocol.language)")
                .font(.system(size: 12)).foregroundColor(Color(hex: "#9398A1"))
            Spacer(minLength: 8)
            status
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(1)
        }
    }

    private var dotColor: String {
        switch dictation.phase {
        case .recording: return "#F43F5E"
        case .starting, .finishing: return "#F5A524"
        case .done: return "#34D399"
        case .failed: return "#F4505E"
        case .idle: return offline ? "#F5A524" : "#8E939C"
        }
    }

    @ViewBuilder private var status: some View {
        switch dictation.phase {
        case .idle:
            if offline { Text("Service offline") } else { Text("Ready") }
        case .starting:
            Text("Connecting…")
        case .recording:
            if onScreen, let since = dictation.recordingSince {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text("Recording \(Self.clock(context.date.timeIntervalSince(since)))")
                }
            } else {
                Text("Recording")
            }
        case .finishing:
            Text("Transcribing…")
        case .done:
            Text(verbatim: outcomeLine)
        case .failed:
            Text("Error")
        }
    }

    private var outcomeLine: String {
        switch dictation.outcome {
        case .pasted?: return L("Pasted where the cursor was")
        case .copied?: return L("Copied — ⌘V pastes it")
        case .copiedSecureInput?: return L("A password field has the keyboard: copied instead")
        case .copiedNoAccessibility?: return L("Copied: allow Accessibility to paste")
        case nil: return L("Done")
        }
    }

    private var offline: Bool {
        switch dictation.serviceStatus {
        case .offline, .invalidAddress, .notTheService: return true
        default: return false
        }
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        switch dictation.phase {
        case .idle:
            if offline { offlineHelp } else { hint }
        case .starting:
            line(Text("Connecting to the transcription service…"))
        case .recording, .finishing:
            heard
        case .done:
            editor
        case .failed:
            failureView
        }
    }

    private var hint: some View {
        let key = DictationHoldKey(rawValue: state.dictationHoldKey) ?? .default
        return VStack(alignment: .leading, spacing: 3) {
            Text("Click Record and speak, then Stop.")
                .font(.system(size: 13)).foregroundColor(Color(hex: "#C9CCD2"))
            if key != .off {
                Text(verbatim: L("Or hold \(L(key: key.title)) in any app, speak, and let go: the text goes where the cursor is."))
                    .font(.system(size: 11.5)).foregroundColor(Color(hex: "#9398A1"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the service has heard so far. With a streaming backend it grows as
    /// the person speaks; with the offline one it waits for Stop, and says so
    /// rather than looking stuck.
    @ViewBuilder private var heard: some View {
        let text = dictation.transcript.text
        if !text.isEmpty {
            Text(verbatim: text)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: dictation.phase == .finishing ? "#9398A1" : "#C9CCD2"))
                .lineLimit(3)
                .truncationMode(.head)
        } else if dictation.phase == .finishing {
            line(Text("Transcribing what you said…"))
        } else if dictation.transcript.service.map({ !$0.streaming }) ?? false {
            line(Text("Listening… This model writes the text when you stop."))
        } else {
            line(Text("Listening…"))
        }
    }

    @ViewBuilder private var editor: some View {
        if dictation.draft.isEmpty && !editing {
            line(Text("Nothing was heard. Check the microphone and try again."))
        } else {
            TextEditor(text: $dictation.draft)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .scrollContentBackground(.hidden)
                .focused($editing)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Color.white.opacity(editing ? 0.10 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                // Focus by click only, as the reply field: taking it on arrival
                // would pull the cursor out of the app being dictated into.
                .simultaneousGesture(TapGesture().onEnded {
                    NotificationCenter.default.post(name: .islandWantsKeyboard, object: nil)
                    editing = true
                })
        }
    }

    private var offlineHelp: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: L("The transcription service is not running at \(state.dictationServiceURL)."))
                .font(.system(size: 13)).foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(2)
            Text("Start it on this computer with dictation-service/scripts/start.sh, then try again.")
                .font(.system(size: 11.5)).foregroundColor(Color(hex: "#9398A1"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var failureView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: failureTitle)
                .font(.system(size: 13)).foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(2)
            if let detail = failureDetail {
                Text(verbatim: detail)
                    .font(.system(size: 11.5)).foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(2)
            }
            if !dictation.draft.isEmpty {
                Text(verbatim: dictation.draft)
                    .font(.system(size: 11.5)).foregroundColor(Color(hex: "#C9CCD2"))
                    .lineLimit(1).truncationMode(.head)
            }
        }
    }

    private var failureTitle: String {
        switch dictation.failure {
        case .microphoneDenied?:
            return L("Notchy cannot use the microphone. Allow it in System Settings › Privacy & Security › Microphone.")
        case .microphoneUnavailable?:
            return L("No microphone is available.")
        case .invalidAddress?:
            return L("The service address in Settings is not a valid address.")
        case .serviceOffline?:
            return L("The transcription service is not running at \(state.dictationServiceURL).")
        case .service(let code, _)?:
            switch code {
            case "model_loading": return L("The model is still loading. Try again in a few seconds.")
            case "model_failed", "provider_unavailable": return L("The transcription service cannot run the model.")
            default: return L("The transcription service refused the recording.")
            }
        case .connectionLost?:
            return L("The connection to the transcription service dropped. What was heard is kept.")
        case .timedOut?:
            return L("The transcription service took too long to answer.")
        case nil:
            return L("Something went wrong.")
        }
    }

    /// The service's own words, when it gave any: it knows what is missing.
    private var failureDetail: String? {
        if case .service(_, let message)? = dictation.failure, !message.isEmpty { return message }
        if case .serviceOffline? = dictation.failure {
            return L("Start it with dictation-service/scripts/start.sh, then try again.")
        }
        return nil
    }

    private func line(_ text: Text) -> some View {
        text.font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1")).lineLimit(2)
    }

    // MARK: Buttons

    private var controls: some View {
        HStack(spacing: 7) {
            RecordButton(phase: dictation.phase) { dictation.toggleRecording() }
                .fixedSize()
            if dictation.phase == .recording, onScreen {
                LevelMeter(level: dictation.level)
            }
            switch dictation.phase {
            case .done where !dictation.draft.isEmpty:
                PrimaryButton(L("Copy")) { dictation.copyDraft() }
                if dictation.trigger == .button {
                    SecondaryButton(L("Paste in app")) { dictation.pasteDraft() }
                }
                SecondaryButton(L("Discard")) { dictation.discard() }
            case .failed:
                if !dictation.draft.isEmpty {
                    SecondaryButton(L("Copy")) { dictation.copyDraft() }
                }
                if dictation.failure == .microphoneDenied, let url = VoiceRecorder.microphoneSettingsURL {
                    SecondaryButton(L("Open Settings")) { NSWorkspace.shared.open(url) }
                }
            case .idle where offline:
                SecondaryButton(L("Check again")) { Task { await dictation.refreshService() } }
            default:
                EmptyView()
            }
            Spacer(minLength: 0)
            modelLine
        }
    }

    /// Which model, and whether text comes while speaking — said plainly, so
    /// an offline backend is not mistaken for a broken one.
    @ViewBuilder private var modelLine: some View {
        if let info = dictation.transcript.service ?? serviceInfo {
            Text(verbatim: info.streaming ? L("\(info.modelName) · live") : L("\(info.modelName) · text at the end"))
                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#6B7079"))
                .lineLimit(1)
                // The buttons come first: this is what gives way.
                .layoutPriority(-1)
        }
    }

    private var serviceInfo: DictationServiceInfo? {
        switch dictation.serviceStatus {
        case .ready(let h), .loading(let h), .broken(let h): return h.info
        default: return nil
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The card's main control: a red pill that records, and stops.
private struct RecordButton: View {
    let phase: DictationController.Phase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    if phase == .starting || phase == .finishing {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Image(systemName: recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .frame(width: 14, height: 14)
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color(hex: phase == .finishing ? "#4B4F57" : "#E11D48"))
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(phase == .finishing)
        .accessibilityLabel(Text(title))
    }

    private var recording: Bool { phase == .recording || phase == .starting }

    private var title: String {
        switch phase {
        case .starting, .recording: return L("Stop")
        case .finishing: return L("Transcribing…")
        case .idle, .done, .failed: return L("Record")
        }
    }
}

/// Five bars for the microphone's level, so a dictation that hears nothing
/// looks like it.
private struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let lit = Float(i) < level * 5 + 0.2
                Capsule()
                    .fill(Color(hex: lit ? "#FB7185" : "#3A3D44"))
                    .frame(width: 3, height: 5 + CGFloat(i % 3) * 3 + (lit ? CGFloat(level) * 8 : 0))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}
