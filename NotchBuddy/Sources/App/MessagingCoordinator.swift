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
import Security

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
        Self.forgetClickMassa()

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
        case .ato:        AtoClient.shared.connect(userInitiated: true)
        case .whatsapp:   WhatsAppWebController.shared.connect()
        }
    }

    /// ClickMassa was removed; what it left behind goes with it. Its Keychain
    /// items held a password, which is not something to leave lying around
    /// for an integration that no longer exists. Idempotent and cheap, so it
    /// simply runs at every start.
    private static func forgetClickMassa() {
        // One account at a time: on the Mac a delete by service alone removes
        // only the first match, and left the password behind when it was tried.
        for account in ["email", "password", "sessionToken"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.cauarati.Notchy.ClickMassa",
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
        for key in ["clickMassaServerURL", "clickMassaOpenTarget"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func sync(active: Set<String>) {
        // The system prompt is worth showing to someone who has just switched a
        // chat pill on, and to nobody else -- so it is asked for here rather
        // than at launch.
        if MessageSource.allCases.contains(where: { active.contains($0.pillID) }) {
            MessageNotifier.shared.prepare()
        }

        if active.contains(MessageSource.mattermost.pillID) {
            MattermostClient.shared.connectIfConfigured()
        } else {
            MattermostClient.shared.disconnect()
        }

        if active.contains(MessageSource.ato.pillID) {
            AtoClient.shared.connectIfConfigured()
        } else {
            AtoClient.shared.disconnect()
        }

        if active.contains(MessageSource.whatsapp.pillID) {
            WhatsAppWebController.shared.connectIfConfigured()
        } else {
            WhatsAppWebController.shared.disconnect()
        }
    }
}
