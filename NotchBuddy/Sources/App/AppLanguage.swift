import Foundation

/// The languages Coucou ships, plus the one that defers to macOS.
///
/// A string raw value rather than an enum case alone, and the same spellings the
/// Windows and Linux preference uses -- see windows/src/core/i18n.ts. The
/// translations themselves are generated into `<lang>.lproj/Localizable.strings`
/// from i18n/catalog.json; nothing here holds a translated string except the
/// language names, which are written in their own language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case es
    case ptBR = "pt-BR"

    var id: String { rawValue }

    /// Every language names itself, the way language menus do everywhere else:
    /// someone looking for their own language should not have to read English
    /// to find it.
    var label: String {
        switch self {
        case .system: return L("Same as system")
        case .en:     return "English"
        case .es:     return "Español"
        case .ptBR:   return "Português (Brasil)"
        }
    }

    /// `.system` answered against what macOS was actually asked for.
    ///
    /// Portuguese from Portugal lands on the Brazilian strings rather than on
    /// English: the two are close enough that the wrong Portuguese beats no
    /// Portuguese. Anything else falls to English, which is what every string
    /// is keyed by, so it is also the one language that cannot be missing.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        for tag in Locale.preferredLanguages {
            let code = tag.lowercased()
            if code.hasPrefix("pt") { return .ptBR }
            if code.hasPrefix("es") { return .es }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }

    var locale: Locale { Locale(identifier: resolved.rawValue) }

    /// Read straight from defaults rather than from `AppState`, because the
    /// message clients that need a translated error are not on the main actor
    /// and this has to answer from whatever thread asks.
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system
    }
}

extension Notification.Name {
    /// Posted when the language changes. SwiftUI rebuilds itself from the
    /// environment; the menu bar is AppKit and has to be told.
    static let languageChanged = Notification.Name("languageChanged")
}
