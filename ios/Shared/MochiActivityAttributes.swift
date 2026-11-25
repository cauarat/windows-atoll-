import ActivityKit
import Foundation

// MARK: - Mochi on the Lock Screen and in the Dynamic Island
//
// Shared by the app, which starts and updates the activity while it runs, and the widget extension,
// which draws it. Everything the widget shows is in the content state: the app and the extension
// share no storage.

struct MochiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var agent: String
        var project: String?
        /// A BotState raw value.
        var state: String
        var detail: String
        var color: String?
        /// A permission request or a question is waiting.
        var waiting: Bool
        var stepIndex: Int
        var stepCount: Int
        var accessory: String?
        var eye: String?
        var shape: String?
        var others: Int
    }

    var computer: String
}
