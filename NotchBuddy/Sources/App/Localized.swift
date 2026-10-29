import Foundation
import SwiftUI

/// The translation of a literal into the language the user picked, interpolation
/// and all: `L("Server returned \(code)")` looks up `"Server returned %lld"`.
///
/// SwiftUI needs none of this: a `Text("Enable sounds")` literal is a
/// `LocalizedStringKey` and resolves itself against the environment's locale,
/// which the root views set. This is for everything that is not SwiftUI -- menu
/// items, window titles, notifications, the errors the message clients raise --
/// and it is deliberately bundle-explicit rather than relying on the process's
/// idea of its own language, which only changes at launch.
///
/// A missing key returns the key, which is the English string. That is the whole
/// reason the catalogue is keyed by English: a translation nobody wrote yet
/// degrades to a sentence rather than to `settings.general.sound.enable`.
func L(_ value: String.LocalizationValue) -> String {
    guard let bundle = localizationBundle() else { return String(localized: value) }
    return String(localized: value, bundle: bundle)
}

/// The same, for a string only known at run time -- an enum's `title`, a pill's
/// name, a verb from the hook server. It cannot be an overload of the above:
/// a `String` variable does not convert to a `LocalizationValue` on its own,
/// and a literal would then have two equally good ways to be read.
func L(key: String) -> String {
    guard let bundle = localizationBundle() else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

/// The .lproj the chosen language lives in. Explicit rather than letting
/// Foundation consult the process's own idea of its language, which is fixed
/// at launch and would need a relaunch to change.
private func localizationBundle() -> Bundle? {
    let lang = AppLanguage.current.resolved
    guard let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj") else { return nil }
    return Bundle(path: path)
}

extension Text {
    /// A label that arrives as a `String` rather than as a literal -- an enum's
    /// `title`, a pill's name, a verb from the hook server.
    ///
    /// `Text(someString)` is verbatim and would never be translated, which is
    /// the quiet way half a translation ships.
    init(loc key: String) { self.init(LocalizedStringKey(key)) }
}

/// Wraps a window's root view so that every `Text` literal inside it resolves
/// against the chosen language, and so that changing the language rebuilds the
/// tree instead of leaving strings resolved a language ago.
///
/// The observation has to live in a `View`: the hosting views are built once
/// and cached for the life of the app, so reading `AppState.shared.language`
/// where one is constructed would read it exactly once.
struct Localizing<Content: View>: View {
    @ObservedObject private var state = AppState.shared
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .environment(\.locale, state.language.locale)
            .id(state.language)
    }
}
