import AVFoundation
import SwiftUI
import UIKit

// MARK: - Pairing
//
// The first screen: Mochi, one sentence on what this is, and the two ways in — scan the QR code the
// computer shows, or paste its link. Either way the app names the computer and asks before it pairs.
// The camera runs only on the scan screen, reads one code, and nothing of it is stored or sent.

struct PairingView: View {
    @EnvironmentObject private var store: PhoneStore
    @State private var scanning = false
    @State private var badLink = false

    var body: some View {
        ZStack {
            Color(hex: "#0E0F11").ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    SizedMochi(state: .idle, color: nil, character: MochiCharacter(), diameter: 92)
                        .frame(width: 160, height: 160)
                    Text("Notchy")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(IslandPalette.text)
                    Text("Your computer does the work. Mochi keeps you in the loop when you step away.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.horizontal, 30)
                }
                .padding(.top, 60)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity)
                .background(IslandShape(cornerRadius: 34, topRadius: 0).fill(Color.black).ignoresSafeArea(edges: .top))

                VStack(alignment: .leading, spacing: 12) {
                    step(1, "On your computer, open Notchy's Settings → General → Phone.")
                    step(2, "Turn on “Show my agent sessions on my phone”, then click Show the pairing code.")
                    step(3, "Scan it here. Your phone and your computer must be on the same Wi-Fi.")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CardBackground(wash: nil))
                .padding(.horizontal, 14)
                .padding(.top, 18)

                Spacer()

                VStack(spacing: 4) {
                    PrimaryButton("Scan the pairing code", systemImage: "qrcode.viewfinder") { scanning = true }
                    SecondaryButton("Paste the link") {
                        if let text = UIPasteboard.general.string, store.offer(link: text) { return }
                        badLink = true
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $scanning) {
            ScannerSheet { code in
                scanning = false
                if !store.offer(link: code) { badLink = true }
            }
        }
        .alert("That is not a Notchy pairing link", isPresented: $badLink) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy the link under the QR code in Notchy's Settings on your computer, or scan the code itself.")
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(n)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#0B0C0E"))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(hex: "#F5F6F8")))
            Text(text)
                .font(.system(size: 13.5))
                .foregroundColor(Color(hex: "#C9CDD4"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Pair with …?" — shown for every link, wherever it came from.
struct PairConfirm: ViewModifier {
    @EnvironmentObject private var store: PhoneStore

    func body(content: Content) -> some View {
        content.alert(
            Text("Pair with \(store.pendingPairing?.name ?? "")?"),
            isPresented: Binding(get: { store.pendingPairing != nil }, set: { if !$0 { store.pendingPairing = nil } })
        ) {
            Button("Cancel", role: .cancel) { store.pendingPairing = nil }
            Button("Pair") {
                store.confirmPairing()
                Notifications.shared.requestPermission()
            }
        } message: {
            if let p = store.pendingPairing {
                Text("This phone will see your agents on \(p.name) and can allow or deny its commands. Address: \(p.host):\(String(p.port))")
            }
        }
    }
}

// MARK: - The camera

struct ScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if denied {
                VStack(spacing: 10) {
                    Text("Notchy can't use the camera")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(IslandPalette.text)
                    Text("Allow the camera in the iPhone's Settings → Notchy, or paste the link instead.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .multilineTextAlignment(.center)
                    SecondaryButton("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                .padding(30)
            } else {
                QRCameraView(onCode: onCode, onDenied: { denied = true })
                    .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 240, height: 240)
                VStack {
                    Spacer()
                    Text("Point at the code in Notchy's Settings on your computer.")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(.bottom, 50)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
    }
}

/// AVFoundation's own QR reader: no library, nothing leaves the phone.
struct QRCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let c = QRCameraController()
        c.onCode = onCode
        c.onDenied = onDenied
        return c
    }

    func updateUIViewController(_ controller: QRCameraController, context: Context) {}
}

final class QRCameraController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onDenied: (() -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    if granted { self?.configure() } else { self?.onDenied?() }
                }
            }
        default:
            onDenied?()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        Self.run(session, start: true)
    }

    /// startRunning blocks, so it goes to a background queue — from a nonisolated function, so the closure
    /// does not inherit the controller's main-actor isolation (which would trap off the main queue).
    private nonisolated static func run(_ session: AVCaptureSession, start: Bool) {
        let box = SessionBox(session: session)
        DispatchQueue.global(qos: .userInitiated).async {  // swift-concurrency-ok: formed in a nonisolated static func, so it carries no main-actor isolation
            if start { box.session.startRunning() } else { box.session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Self.run(session, start: false)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              code.lowercased().hasPrefix("notchy://") else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}

/// AVCaptureSession is thread-safe for start and stop, but not marked Sendable.
private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}
