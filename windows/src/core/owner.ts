// Whose face the island is wearing — the twin of NotchBuddy/Sources/App/IslandOwner.swift.
//
// There is one Mochi, drawn over every view, and he takes his position from the
// view. His character, colour — and, for Ato, whether he is Ato at all — have to
// come from the same place, or a card that speaks for one service wears another
// pill's face. The rule, in one line: **when the view speaks for a service, the
// view decides; otherwise focus decides.** An Ato message card is Ato's, whoever
// was clicked last.
//
// Pure, so tests/island-owner-parity.ts can hold it to the Swift one.

import type { IslandViewName } from "./layout";

export type IslandOwner =
  | { kind: "pill"; id: string }
  /** The queue that stands for every service at once, which wears its own face. */
  | { kind: "everyService" }
  | { kind: "none" };

const pill = (id: string | null | undefined): IslandOwner => (id ? { kind: "pill", id } : { kind: "none" });

/**
 * - `listSource`: pill id of the service whose queue is open, if one is.
 * - `listShowsAll`: the Notifications queue is open, over every service.
 * - `activeMessageSource`: pill id behind the single message on the card.
 * - `focusId`: the focused pill, which answers for every other view.
 */
export function islandOwner(
  view: IslandViewName, listSource: string | null, listShowsAll: boolean,
  activeMessageSource: string | null, focusId: string | null,
): IslandOwner {
  switch (view) {
    case "messages":
      if (listShowsAll) return { kind: "everyService" };
      return pill(listSource ?? focusId);
    case "message":
      return pill(activeMessageSource ?? focusId);
    default:
      return pill(focusId);
  }
}
