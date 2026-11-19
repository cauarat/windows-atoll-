import Foundation

// The welcome a first run shows before the island opens, as data: which screens,
// in what order, where a run of it stands, and whether this launch shows it at all.
//
// Foundation only — scripts/test-welcome.sh compiles it on its own — and mirrored
// by windows/src/core/onboarding.ts, which tests/welcome-parity.ts holds to the
// same answers. What the screens look like is OnboardingView.swift's business.

/// The seven screens, in the order they come.
///
/// The raw values are what `NOTCHY_ONBOARDING=<step>` takes, to open the welcome
/// on one screen for a screenshot — nothing here can click "Continue".
enum OnboardingStep: String, CaseIterable {
    case welcome, name, language, look, tools, startup, ready
}

/// Where a run of the welcome stands.
///
/// A value, kept by the window rather than by the view: changing the language
/// rebuilds every view under `Localizing`, and a screen counter in `@State` would
/// go back to the start the moment someone picked Português.
struct OnboardingFlow: Equatable {
    static let steps = OnboardingStep.allCases

    private(set) var index = 0

    init(start: OnboardingStep = .welcome) {
        index = Self.steps.firstIndex(of: start) ?? 0
    }

    var step: OnboardingStep { Self.steps[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == Self.steps.count - 1 }

    mutating func advance() { index = min(index + 1, Self.steps.count - 1) }
    mutating func back() { index = max(index - 1, 0) }

    /// "2 of 5" for the five questions. Nil on the hello and on the last screen,
    /// which ask nothing and so carry no progress row.
    var progress: (current: Int, total: Int)? {
        guard step != .welcome, step != .ready else { return nil }
        return (index, Self.steps.count - 2)
    }
}

enum OnboardingGate {
    /// What a finished welcome is stamped with. Raise it when the welcome gains a
    /// screen everybody should see: whoever finished an older one is shown the new
    /// one, once. Stored under `onboardingVersion`, the key Windows uses too.
    static let version = 1

    /// Whether this launch opens on the welcome. Not while Notchy is switched off:
    /// the welcome ends by opening the island, and an island that is off cannot.
    static func shouldShow(seen: Int, enabled: Bool) -> Bool {
        enabled && seen < version
    }
}
