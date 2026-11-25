// What Copy on a message card copies — the twin of `MessageCopy.content` in
// MessageCopy.swift, checked against it by scripts/test-message-copy.sh.
//
// What the sender sent — their words, their photo, their voice message, their
// PDF — and never what the card says about it: "📷 Photo" and "📎 Sent a file"
// are the card talking. No imports, so the parity test can run it under Node
// alone.

export type CopyKind = "text" | "photo" | "voice" | "files";

/** A file Copy hands on — `MessageFile` in bridge.ts, `InboxFile` on the Mac. */
export interface CopyFile {
  fileId: string;
  name: string;
  mimeType: string;
  byteCount: number;
}

/** What a message may carry that Copy cares about. */
export interface Copyable {
  text?: string | null;
  photo?: { fileId: string; name: string; mimeType: string; byteCount: number } | null;
  audio?: unknown | null;
  /** Every file on the message, the photo's own among them. */
  files?: CopyFile[] | null;
}

/**
 * What there is to copy, or null when there is nothing real to hand on.
 *
 * The voice message and the photo come first, in the order the card draws
 * them; then the files the card only says arrived. They are what was sent,
 * and any words are beside them.
 */
export function copyKind(message: Copyable): CopyKind | null {
  if (message.audio) return "voice";
  if (message.photo) return "photo";
  if (message.files && message.files.length > 0) return "files";
  return message.text && message.text.trim() !== "" ? "text" : null;
}

/**
 * The files Copy puts on the clipboard: for a photo, the one the card shows
 * and then the post's others — the rest of an album, a PDF sent with it,
 * `MessageCopy.photo`'s `alongside`; for files, all of them. Empty for words
 * and for a voice message, which is copied as its own audio file.
 */
export function copyFiles(message: Copyable): CopyFile[] {
  const files = message.files ?? [];
  switch (copyKind(message)) {
    case "photo": {
      const photo = message.photo!;
      const shown: CopyFile = {
        fileId: photo.fileId, name: photo.name, mimeType: photo.mimeType, byteCount: photo.byteCount,
      };
      return [shown, ...files.filter((file) => file.fileId !== photo.fileId)];
    }
    case "files":
      return files;
    default:
      return [];
  }
}
