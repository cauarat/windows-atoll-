import SwiftUI
import WebKit

// MARK: - Host for the island web chat

/// An empty container the controller attaches its web view into.
///
/// Construction is free, which matters: `IslandContentView` builds every `IslandView` at
/// once, so this host is created for the inactive case too. Nothing loads until
/// `WebChatController.activate(in:)` passes its state guards.
final class WebChatHostNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            WebChatController.shared.activate(in: self)
        } else {
            WebChatController.shared.deactivate()
        }
    }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }
}

struct WebChatHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> WebChatHostNSView { WebChatHostNSView() }
    func updateNSView(_ nsView: WebChatHostNSView, context: Context) {}

    /// live → warm, never a teardown: leaving the view must not cost the conversation.
    static func dismantleNSView(_ nsView: WebChatHostNSView, coordinator: ()) {
        WebChatController.shared.deactivate()
    }
}

// MARK: - The island view

/// Laid out like `NotchSiteView`, the screen it sits beside: its own 34pt header, then the
/// page filling the card.
struct WebChatIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var web = WebChatController.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 34)
                .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "#141518"))

                WebChatHostView()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(web.loadState == .ready ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: web.loadState == .ready)

                switch web.loadState {
                case .blocked(let code):
                    failure("ChatGPT is refusing the built-in browser (HTTP \(code)).",
                            detail: "Open it in your browser instead, or try again.")
                case .failed(let why):
                    failure("Could not reach ChatGPT.", detail: why)
                case .idle, .loading:
                    TypingDotsView()
                case .ready:
                    EmptyView()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .foregroundColor(Color(hex: "#F5F6F8"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Mochi keeps his place on the screen that replaced his chat.
            BotCanvasView(state: state)
                .frame(width: 34, height: 34)
                .allowsHitTesting(false)
            Text("ChatGPT")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            HStack(spacing: 14) {
                headerButton("arrow.clockwise") { WebChatController.shared.reload() }
                // The page holds the island open now, so there has to be a way
                // out that is not a keystroke. Same mark, same place and same
                // notification as the site's, which is the screen this one was
                // laid out against.
                headerButton("xmark") {
                    NotificationCenter.default.post(name: .closeNotchSite, object: nil)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func headerButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C"))
                // `xmark` is mostly gap, and a glyph takes the mouse only where
                // it has ink. Grown past its own frame so the target is bigger
                // without moving anything in the row.
                .frame(width: 18, height: 18)
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
    }

    private func failure(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Try again") { WebChatController.shared.reload() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(hex: "#1D1F23"))
                .clipShape(Capsule())
        }
        .padding(20)
    }
}
