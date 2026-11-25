// What Copy on a message card copies — the twin of `MessageCopy.content` in
// MessageCopy.swift, checked against it by scripts/test-message-copy.sh.
//
// What the sender sent — their words, their photo, their voice message — and
// never what the card says about it: "📷 Photo" and "📎 Sent a file" are the
// card talking. No imports, so the parity test can run it under Node alone.

export type CopyKind = "text" | "photo" | "voice";

/** The three things a message may carry that Copy cares about. */
export interface Copyable {
  text?: string | null;
  photo?: unknown | null;
  audio?: unknown | null;
}

/**
 * What there is to copy, or null when there is nothing real to hand on: a file
 * the card only says arrived, which the app neither shows nor fetches.
 *
 * The voice message and the photo come first, in the order the card draws
 * them: they are what was sent, and any words are beside them.
 */
export function copyKind(message: Copyable): CopyKind | null {
  if (message.audio) return "voice";
  if (message.photo) return "photo";
  return message.text && message.text.trim() !== "" ? "text" : null;
}
