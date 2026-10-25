import Foundation

/// Whose face the island is wearing.
///
/// There is one Mochi, drawn over every view by `BotPlacement` rather than
/// inside any of them, and for a long time he took his position from
/// `state.view` while taking his character and colour from whatever pill held
/// focus. Nothing reconciled the two, so a click that moved focus without
/// moving the view left Now Playing's character sitting in Mattermost's card —
/// a red heart with a sprout, inside a blue service's list.
///
/// The rule, in one line: **when the view speaks for a service, the view
/// decides; otherwise focus decides.** A message list is Mattermost's because
/// it is showing Mattermost's messages, whoever was clicked afterwards.
///
/// Deliberately knows nothing of `AppState` or `PillCatalog`: this is the one
/// piece of the bug that can be tested without opening the island, which on a
/// Mac that cannot be driven from a script is the difference between a proof
/// and an opinion. `everyService` is returned rather than the Notifications
/// pill id for the same reason — naming the pill is the caller's job.
enum IslandOwner {

    enum Owner: Equatable {
        /// One pill, by id.
        case pill(String)
        /// The queue that stands for every service at once, which wears its
        /// own face rather than picking one of theirs.
        case everyService
        /// Nothing names an owner; the default character is right.
        case none
    }

    /// Who the character and colour on screen belong to.
    ///
    /// - Parameters:
    ///   - view: what the island is actually showing.
    ///   - listSource: pill id of the service whose queue is open, if one is.
    ///   - listShowsAll: the Notifications queue is open, over both services.
    ///   - activeMessageSource: pill id behind the single message on the card.
    ///   - focusID: the focused pill, which answers for every other view.
    static func owner(view: IslandView,
                      listSource: String?,
                      listShowsAll: Bool,
                      activeMessageSource: String?,
                      focusID: String?) -> Owner {
        switch view {
        case .messages:
            if listShowsAll { return .everyService }
            return pill(listSource ?? focusID)
        case .message:
            return pill(activeMessageSource ?? focusID)
        default:
            // Home, the agent views, the timer, the site: none of them belongs
            // to a service, so the focused pill is the honest answer.
            return pill(focusID)
        }
    }

    private static func pill(_ id: String?) -> Owner {
        guard let id, !id.isEmpty else { return .none }
        return .pill(id)
    }
}
