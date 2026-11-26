import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

#if !APPSTORE

// MARK: - Settings → General → Phone
//
// One box, in the style of the others in General. Off by default: turning the switch on starts the
// listener, turning it off stops everything. The pairing code (a QR code and the link) is shown only
// after a click, because whoever holds it can pair.

enum PhoneLinkQR {
    /// The link as a QR code, black on white with a quiet zone, scaled up without smoothing.
    static func image(for text: String, side: CGFloat = 180) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(side / output.extent.width))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let padded = scaled.composited(over: CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -12, dy: -12)))
        let rep = NSCIImageRep(ciImage: padded)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

struct PhoneLinkSettingsBox: View {
    @ObservedObject private var link = PhoneLinkService.shared
    @AppStorage(PhoneLinkService.enabledKey) private var enabled = false
    @AppStorage(PhoneLinkDefaultsFeatures.chatKey) private var chat = false
    @State private var showCode = false
    @State private var pairing: String?

    var body: some View {
        GroupBox("Phone") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Link my phone to this Mac", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        showCode = false
                        pairing = nil
                        link.setEnabled(on)
                    }
                note("Notchy for iPhone and Android connects to this Mac over your local network, nothing in between. "
                     + "Off, nothing listens and nothing is announced on the network.")
                if enabled {
                    status
                    if link.running {
                        Button(showCode ? "Hide the pairing code" : "Show the pairing code") {
                            showCode.toggle()
                            pairing = showCode ? link.pairingLink() : nil
                        }
                        if showCode { pairingCode }
                    }
                }
                Divider().padding(.vertical, 2)
                Toggle("Let the phone chat with my AI providers", isOn: $chat)
                    .disabled(!enabled)
                    .onChange(of: chat) { _, _ in link.switchesChanged() }
                note("Your phone sends text and gets Mochi's answer back. Your Mac calls the providers set up in Chat, with its own keys: no key ever leaves this Mac.")
            }
            .padding(6)
        }
    }

    @ViewBuilder private var status: some View {
        if let error = link.error {
            plain(L("The phone link could not start: \(error)"))
        } else if link.running {
            let port = Int(link.port)
            plain(link.phones == 0
                  ? L("Listening on port \(port). No phone connected.")
                  : L("Listening on port \(port). Phones connected: \(link.phones)."))
        }
    }

    @ViewBuilder private var pairingCode: some View {
        if let text = pairing {
            note("Open Notchy on your phone and scan this code, or paste the link. Your phone and this Mac must be on the same Wi-Fi.")
            if let image = PhoneLinkQR.image(for: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .accessibilityLabel(Text("Pairing code"))
            }
            Text(verbatim: text)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Copy the link") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    // Concealed and transient, so clipboard managers do not keep the pairing secret.
                    pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                    pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
                }
                Button("Pair again") {
                    link.pairAgain()
                    pairing = link.pairingLink()
                }
            }
            note("Pair again makes a new code: the phone paired with the old one is disconnected and has to scan again.")
        } else {
            note("This Mac has no address on a local network right now. Join a Wi-Fi or plug in a cable, then try again.")
        }
    }

    /// A catalogue key (English), translated where it is drawn.
    private func note(_ key: String) -> some View {
        Text(loc: key)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Text already translated.
    private func plain(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#endif
