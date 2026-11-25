// Copy on a message card, and what its button shows meanwhile — the twin of
// `MessageCopier` in MessageCopyButton.swift.
//
// One for the island, so the pop-up and Home — which can show the same
// message — agree on whether it was just copied. Only the newest copy lands
// its answer: a photo still downloading when something else is copied does
// not then say it is done.

import { Bridge } from "../core/bridge";
import { copyFiles, copyKind } from "../core/messageCopy";
import { Sound } from "../core/sound";
import { State, type InboxMessage } from "../core/state";
import { t } from "../core/i18n";

let copyingId: string | null = null;
let copiedId: string | null = null;
let failure: { id: string; reason: string } | null = null;
let generation = 0;
let settle: ReturnType<typeof setTimeout> | null = null;

/** Whether the card offers Copy at all. */
export function canCopy(message: InboxMessage): boolean {
  return copyKind(message) != null;
}

/** The photo, audio or files are being fetched to be copied. */
export function copying(id: string): boolean {
  return copyingId === id;
}

/** Just copied — the button says so for a moment. */
export function copied(id: string): boolean {
  return copiedId === id;
}

/** Why the last copy of this message failed, for the card to say in the body's place. */
export function failureFor(id: string): string | null {
  return failure?.id === id ? failure.reason : null;
}

export function copy(message: InboxMessage): void {
  const kind = copyKind(message);
  if (!kind) return;
  const mine = ++generation;
  if (settle) clearTimeout(settle);
  copiedId = null;
  failure = null;
  copyingId = kind === "text" ? null : message.id;
  State.notify();

  let work: Promise<void>;
  let reason: string;
  if (kind === "voice" && message.audio) {
    work = Bridge.copyMessageVoice(message.audio.storageFileId, message.audio.fileName);
    reason = t("Couldn't copy the audio");
  } else if (kind === "photo" && message.photo && copyFiles(message).length === 1) {
    const photo = message.photo;
    work = Bridge.copyMessagePhoto(photo.fileId, photo.name, photo.mimeType);
    reason = t("Couldn't copy the photo");
  } else if (kind === "photo" || kind === "files") {
    // A photo among others goes as files, every one of them: the clipboard
    // here holds one image or a list of files, and the list is what was sent.
    const files = copyFiles(message);
    work = Bridge.copyMessageFiles(message.source, files);
    reason = files.length === 1 ? t("Couldn't copy the file") : t("Couldn't copy the files");
  } else {
    work = Bridge.copyMessageText(message.text ?? "");
    reason = t("Couldn't copy the message");
  }
  void work.then(
    () => finish(message.id, mine, null),
    () => finish(message.id, mine, reason),
  );
}

function finish(id: string, mine: number, error: string | null) {
  if (mine !== generation) return;
  copyingId = null;
  if (error) {
    failure = { id, reason: error };
  } else {
    copiedId = id;
    Sound.play("blip");
  }
  State.notify();
  settle = setTimeout(() => {
    if (mine !== generation) return;
    copiedId = null;
    failure = null;
    State.notify();
  }, error ? 4000 : 1600);
}
