import AppKit
import SwiftUI
import WebKit

// MARK: - The site integration
//
// One site, reached from a small icon that sits beside the notch instead of
// from a pill in the island. Clicking it opens the page inside the island,
// which stretches to the largest size the screen allows for as long as the
// page is up, and folds back to its usual self once the page is closed.

enum NotchSite {

    /// The site the icon opens. A literal https URL, so the parse cannot fail.
    static let url = URL(string: "https://caus-macbook-pro.tail8e18f9.ts.net/")!

    /// Shown in the island header until the page reports a title of its own.
    static var hostLabel: String { url.host ?? "Site" }

    // MARK: Icon geometry
    //
    // The icon lives outside the notch, clear of the compact island — the
    // widest resting state — so a running session never covers it. The maths
    // lives in `NotchSiteGeometry`, which has no AppKit in it and is tested.

    static func iconSide(notchHeight: CGFloat) -> CGFloat {
        NotchSiteGeometry.iconSide(notchHeight: notchHeight)
    }

    static func iconCenterOffsetX(notchWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        NotchSiteGeometry.iconCenterOffsetX(notchWidth: notchWidth, notchHeight: notchHeight)
    }

    static func iconTopInset(notchHeight: CGFloat) -> CGFloat {
        NotchSiteGeometry.iconTopInset(notchHeight: notchHeight)
    }

    static func iconFrame(panelSize: CGSize,
                          notchWidth: CGFloat, notchHeight: CGFloat) -> CGRect {
        NotchSiteGeometry.iconFrame(panelSize: panelSize,
                                    notchWidth: notchWidth, notchHeight: notchHeight)
    }

    // MARK: Island and panel size while the page is up

    /// Used until a screen has been measured.
    static let fallbackIslandSize = CGSize(width: IslandConst.expandedWidth, height: 600)

    static func islandSize(for screen: NSScreen) -> CGSize {
        NotchSiteGeometry.islandSize(screen: screen.frame,
                                     dockTop: screen.visibleFrame.minY)
    }

    static func panelSize(for screen: NSScreen) -> CGSize {
        NotchSiteGeometry.panelSize(screen: screen.frame,
                                    dockTop: screen.visibleFrame.minY)
    }
}

// MARK: - The mark

/// One of the mark's broken rings. Angles are degrees from the right, growing
/// counter-clockwise, the way the artwork was measured; the view's y axis points
/// down, so the sine is subtracted rather than added.
struct NotchSiteArc: Shape {
    let radius: CGFloat
    let from:   Double
    let to:     Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let steps = max(12, Int((to - from).magnitude / 2))
        var p = Path()
        for i in 0...steps {
            let a = (from + (to - from) * Double(i) / Double(steps)) * .pi / 180
            let pt = CGPoint(x: c.x + radius * CGFloat(cos(a)),
                             y: c.y - radius * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// The mark itself: a dot with two rings cut open towards the upper left, the
/// outer one wider than the inner. Every ratio measured off the artwork and
/// held relative to `side`, so it stays sharp wherever it is drawn — on its own
/// tile below, or straight onto the island's border in the edge ring.
struct NotchSiteGlyph: View {
    var side: CGFloat
    var ink: Color

    private var dotRadius:   CGFloat { side * 0.059 }
    private var innerRadius: CGFloat { side * 0.126 }
    private var outerRadius: CGFloat { side * 0.221 }
    private var innerStroke: CGFloat { max(0.6, side * 0.047) }
    private var outerStroke: CGFloat { max(0.6, side * 0.050) }

    var body: some View {
        ZStack {
            Circle()
                .fill(ink)
                .frame(width: dotRadius * 2, height: dotRadius * 2)

            NotchSiteArc(radius: innerRadius, from: 174, to: 466)
                .stroke(ink, style: StrokeStyle(lineWidth: innerStroke, lineCap: .round))

            NotchSiteArc(radius: outerRadius, from: 227, to: 452)
                .stroke(ink, style: StrokeStyle(lineWidth: outerStroke, lineCap: .round))
        }
        .frame(width: side, height: side)
    }
}

/// The mark on its own dark rounded tile, as the artwork has it. Drawn rather
/// than shipped as an image, so it stays sharp at any size.
struct NotchSiteIcon: View {
    var side: CGFloat
    var highlighted: Bool = false

    private var corner:       CGFloat { side * 0.212 }
    private var borderStroke: CGFloat { max(0.5, side * 0.030) }

    private var ink:    Color { Color(hex: highlighted ? "#C3C9D6" : "#888FA0") }
    private var border: Color { Color(hex: highlighted ? "#454A50" : "#303234") }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(hex: "#15191D"))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(border, lineWidth: borderStroke)
                )

            NotchSiteGlyph(side: side, ink: ink)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - The icon beside the notch

/// Sits outside the notch and opens the site. Fades out while the island is
/// expanded, which is exactly when the island would be covering it anyway.
struct NotchSiteLauncher: View {
    @ObservedObject var state: AppState
    @State private var isHovered = false

    private var side: CGFloat { NotchSite.iconSide(notchHeight: state.notchHeight) }
    private var visible: Bool { state.isEnabled && state.mode != .expanded }

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.web)
        } label: {
            NotchSiteIcon(side: side, highlighted: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(NotchSite.hostLabel)
        .scaleEffect(isHovered && visible ? 1.09 : 1)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.18), value: visible)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .frame(width: side, height: side)
    }
}

// MARK: - The page

/// Owns the web view so the header can drive it, and so it goes away with the
/// island rather than idling behind a hidden view.
@MainActor
final class NotchSiteWeb: NSObject, ObservableObject {
    @Published var isLoading  = true
    @Published var canGoBack  = false
    @Published var title      = ""
    @Published var failure: String?

    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        // The default store, so a sign-in survives closing and reopening the page.
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Public API only: the page keeps its own background, and what shows
        // around it matches the card it sits in.
        webView.underPageBackgroundColor = NSColor(Color(hex: "#141518"))
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: NotchSite.url))
    }

    func reload() {
        failure = nil
        if webView.url == nil {
            webView.load(URLRequest(url: NotchSite.url))
        } else {
            webView.reload()
        }
    }

    func goBack() { webView.goBack() }

    /// Called when the island folds. The web view is released with the view
    /// that owned it, but blanking it first makes sure no script outlives the
    /// island by even a frame.
    func stop() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    private func sync() {
        canGoBack = webView.canGoBack
        title = webView.title ?? ""
    }
}

extension NotchSiteWeb: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        failure = nil
        sync()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        sync()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        failure = error.localizedDescription
        sync()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        isLoading = false
        failure = error.localizedDescription
        sync()
    }

    /// The island is not a browser: it follows web links, and hands anything
    /// else — a mail link, a custom scheme that would launch another app — to
    /// the system instead of acting on it itself.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        switch url.scheme?.lowercased() {
        case "http", "https", "about", "blob":
            decisionHandler(.allow)
        default:
            decisionHandler(.cancel)
            // Only a click leaves the island. A page may not launch another app
            // just by navigating itself somewhere.
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

extension NotchSiteWeb: WKUIDelegate {
    /// A link that asks for a new window gets the one window there is.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url,
           safeWebURL(url.absoluteString) != nil {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

struct NotchSiteWebRepresentable: NSViewRepresentable {
    let web: NotchSiteWeb

    func makeNSView(context: Context) -> WKWebView { web.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - The site view

/// The page filling the island. Rendered from `IslandContainer` rather than
/// from the stack that holds every other view, so the web view is built when
/// the site opens and torn down when it closes.
struct NotchSiteView: View {
    @ObservedObject var state: AppState
    @StateObject private var web = NotchSiteWeb()

    private var label: String { web.title.isEmpty ? NotchSite.hostLabel : web.title }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 34)
                .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "#141518"))

                NotchSiteWebRepresentable(web: web)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let failure = web.failure {
                    VStack(spacing: 10) {
                        Text(NotchSite.hostLabel)
                            .font(.system(size: 13, weight: .semibold))
                        Text(failure)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                        Button("Try again") { web.reload() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#1D1F23"))
                            .clipShape(Capsule())
                    }
                    .padding(20)
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
        .onDisappear { web.stop() }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if web.canGoBack {
                    NotchSiteHeaderButton(icon: "chevron.left") { web.goBack() }
                }
                NotchSiteIcon(side: 16)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if web.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.leading, 14)

            Spacer()

            HStack(spacing: 14) {
                NotchSiteHeaderButton(icon: "arrow.clockwise") { web.reload() }
                NotchSiteHeaderButton(icon: "arrow.up.right") {
                    NSWorkspace.shared.open(safeWebURL(web.webView.url?.absoluteString)
                                            ?? NotchSite.url)
                }
                NotchSiteHeaderButton(icon: "xmark") {
                    NotificationCenter.default.post(name: .closeNotchSite, object: nil)
                }
            }
            .padding(.trailing, 16)
        }
    }
}

private struct NotchSiteHeaderButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: isHovered ? "#F5F6F8" : "#8E939C"))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
