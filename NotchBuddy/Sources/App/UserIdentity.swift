import Foundation

// Who Mochi is talking to, and what time of day it is for them.
//
// Foundation only, so scripts/test-welcome.sh can compile it on its own, and
// mirrored line for line by windows/src/core/greetingName.ts — the parity half
// of that suite holds the two to the same answers.

/// First name of the macOS account holder, or nil when the account name is not something
/// you would greet someone by. "Théodore Riant" gives "Théodore"; a login handle like
/// "theodoreriant" or "t.riant2" gives nil, because "Hey theodoreriant!" reads worse than
/// a greeting with no name at all.
func resolveUserFirstName() -> String? {
    firstName(fromFullName: NSFullUserName())
}

/// The macOS first name, read once. `NSFullUserName()` is a system call, and the
/// account's name does not change under a running app — what the user types in
/// Settings does, which is why that is read where it is used instead.
let systemUserFirstName: String? = resolveUserFirstName()

/// The rule behind `resolveUserFirstName()`, apart from where the name comes from: so it
/// can be tested, and so Windows and Linux can apply it to their own account names.
func firstName(fromFullName raw: String) -> String? {
    let fullName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fullName.isEmpty, fullName.count <= maxUserFullNameLength else { return nil }
    guard !looksLikeLoginHandle(fullName) else { return nil }

    guard let first = fullName.split(separator: " ").first.map(String.init),
          !first.isEmpty,
          first.allSatisfy(isNamePart) else { return nil }
    return first
}

/// NSFullUserName() falls back to the short account name when the full name is unset, so a
/// single lowercase word, or one carrying digits or separators, is treated as a handle.
private func looksLikeLoginHandle(_ name: String) -> Bool {
    guard !name.contains(" ") else { return false }
    return name == name.lowercased() || name.contains(where: isHandleMarker)
}

private func isHandleMarker(_ character: Character) -> Bool {
    character.isNumber || "._-@".contains(character)
}

private func isNamePart(_ character: Character) -> Bool {
    character.isLetter || character == "'" || character == "-"
}

private let maxUserFullNameLength = 32

// MARK: - The name the user typed

/// The most a typed name keeps. Room for a first name and a surname or two, and
/// short enough that the greeting under Mochi stays on one line inside the island.
let maxTypedUserNameLength = 40

/// The name typed in Settings (or in the welcome), as Mochi will say it: no space at
/// either end, single spaces inside, at most `maxTypedUserNameLength` characters. Nil
/// when nothing is left, so an empty field falls through to the account's name.
///
/// Stored as typed and cleaned where it is read: cleaning on every keystroke would
/// eat the space between two words while the second one is still being typed.
func cleanedUserName(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let words = raw.split(whereSeparator: { $0.isWhitespace })
    guard !words.isEmpty else { return nil }
    let capped = String(words.joined(separator: " ").prefix(maxTypedUserNameLength))
        .trimmingCharacters(in: .whitespaces)
    return capped.isEmpty ? nil : capped
}

/// What Mochi calls the user: the name they typed, or failing that the account's first
/// name, or nil — and then the greeting simply has no name in it.
func userGreetingName(typed: String?, system: String?) -> String? {
    cleanedUserName(typed) ?? system
}

// MARK: - Time of day

/// The part of the day a greeting belongs to, by the clock on the wall.
///
/// Three, not four. Portuguese and Spanish say "boa noite" / "buenas noches" from
/// nightfall until morning, and English "good evening" is what you say on arriving at
/// any hour after six — "good night" is a goodbye, not a hello.
enum DayPeriod: String, CaseIterable {
    case morning, afternoon, evening

    static func at(hour: Int) -> DayPeriod {
        switch hour {
        case 5..<12:  return .morning
        case 12..<18: return .afternoon
        default:      return .evening
        }
    }

    static func at(_ date: Date, calendar: Calendar = .current) -> DayPeriod {
        at(hour: calendar.component(.hour, from: date))
    }
}
