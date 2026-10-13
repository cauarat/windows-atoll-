// Which pills are configured, and what an unconfigured one says.
//
// This used to carry the integration events too — the Rust side of seven
// pollers emitted them, and a genuinely new invoice or deploy flipped a pill to
// finished, badged it and played a sound. Those seven went with the Mac's
// "Cut Coucou down to what it is used for". What is left is the question the
// idle cards ask: is this one set up at all?

import { Bridge } from "../core/bridge";
import { MESSAGE_SOURCES, NOTIFICATIONS_PILL, PILL_FOR_SOURCE, State } from "../core/state";

/** Which Credential Manager key backs each pill. */
const KEY_FOR: Record<string, string> = {
  // The message sources are configured once their server address is stored;
  // the login and password are checked by the connection, not by this.
  integration_mattermost: "mattermost-url",
  integration_clickmassa: "clickmassa-url",
};

/** Asks Rust which keys exist so the idle cards can say so. */
export async function refreshConfigured() {
  for (const [id, key] of Object.entries(KEY_FOR)) {
    const present = (await Bridge.secretPresent(key)) ?? false;
    const info = State.integrations[id] ?? { data: {}, error: null, loaded: false, configured: false };
    State.integrations[id] = { ...info, configured: present };
  }
  const hooks = State.settings.hooksInstalled;
  const claude = State.integrations.integration_claude ?? {
    data: {}, error: null, loaded: false, configured: false,
  };
  State.integrations.integration_claude = { ...claude, configured: hooks };

  // Notifications has no key of its own: it stands for both message services,
  // so it is configured once either of them is. Without this it drew a red dot
  // and "Key not configured" over a working queue.
  const either = MESSAGE_SOURCES.some((s) => State.integrations[PILL_FOR_SOURCE[s]]?.configured);
  const notifications = State.integrations[NOTIFICATIONS_PILL] ?? {
    data: {}, error: null, loaded: false, configured: false,
  };
  State.integrations[NOTIFICATIONS_PILL] = { ...notifications, configured: either };

  // Now Playing reads what this machine is already playing and talks to
  // nothing, so there is nothing to configure and nothing to warn about.
  const music = State.integrations.integration_music ?? {
    data: {}, error: null, loaded: false, configured: false,
  };
  State.integrations.integration_music = { ...music, configured: true };
  State.notify();
}
