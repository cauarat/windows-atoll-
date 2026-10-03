/*
 * Notchy
 * Copyright (C) 2026 Notchy Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Combine
import Foundation

/// Connects the message sources whose pill is on, and disconnects the rest.
///
/// A separate object rather than logic inside each client: both clients are
/// ported from Atoll almost unchanged, and keeping their connection policy out
/// here means the next upstream fix can be applied to them without untangling
/// Notchy's pill rules first.
///
/// The rule is the one the music pill already follows — nobody who has not
/// switched a source on should have a socket open to it.
@MainActor
final class MessagingCoordinator {
    static let shared = MessagingCoordinator()

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        AppState.shared.$activeIntegrations
            .removeDuplicates()
            .sink { [weak self] integrations in
                self?.sync(active: integrations)
            }
            .store(in: &cancellables)

        sync(active: AppState.shared.activeIntegrations)
    }

    /// Reconnects a source after its credentials change, without waiting for
    /// the pill to be toggled off and on again.
    func reconnect(_ source: MessageSource) {
        guard AppState.shared.activeIntegrations.contains(source.pillID) else { return }
        switch source {
        case .mattermost: MattermostClient.shared.connect()
        case .clickMassa: ClickMassaClient.shared.connect(userInitiated: true)
        }
    }

    private func sync(active: Set<String>) {
        if active.contains(MessageSource.mattermost.pillID) {
            MattermostClient.shared.connectIfConfigured()
        } else {
            MattermostClient.shared.disconnect()
        }

        if active.contains(MessageSource.clickMassa.pillID) {
            ClickMassaClient.shared.connectIfConfigured()
        } else {
            ClickMassaClient.shared.disconnect()
        }
    }
}
