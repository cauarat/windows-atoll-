/**
 * Staging files on a reply: taking them in, saying why one was refused, and
 * letting them go again.
 *
 * The rules live in `core/attachments.ts`, which is pure and checked against
 * the Swift. This is the half that talks to Rust — it asks for sizes, writes
 * pasted bytes somewhere real, and opens the picker.
 *
 * The twin of `ReplyAttachmentStore.swift`.
 */

import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import { Sound } from "../core/sound";
import {
  acceptAttachments, baseName, rejectionMessage,
  type AttachmentCandidate, type ReplyAttachment,
} from "../core/attachments";

/** Stages whatever the rules allow, and says so when some are turned away. */
export function attach(candidates: AttachmentCandidate[]): void {
  if (candidates.length === 0) return;

  const result = acceptAttachments(candidates, State.replyAttachments);

  if (result.accepted.length > 0) {
    State.replyAttachments = [...State.replyAttachments, ...result.accepted];
    Sound.play("attach");
  }
  // One line, however many were refused: the card has room for a sentence,
  // not a list.
  State.replyNotice = result.rejected.length > 0
    ? rejectionMessage(result.rejected[0]!)
    : null;
  State.notify();
}

/**
 * Stages files the OS handed over as paths.
 *
 * Each one goes through `ingestFile` first, which copies it into the inbox and
 * reports its real size — the drop event carries a path and nothing else.
 */
export async function attachPaths(paths: string[]): Promise<void> {
  const candidates: AttachmentCandidate[] = [];
  for (const path of paths) {
    try {
      const file = await Bridge.ingestFile(path);
      candidates.push({ path: file.path, byteCount: file.size });
    } catch (err) {
      // A folder is the common case here, and Rust says so in words.
      State.replyNotice = String(err).replace(/^Error:\s*/, "");
      State.notify();
    }
  }
  attach(candidates);
}

/**
 * Stages files from a paste.
 *
 * The webview's own `DataTransfer` is the only route: Tauri's drag-drop
 * interception does not cover paste, and the Rust clipboard watcher reads
 * text and 40 px thumbnails only.
 */
export async function attachClipboardFiles(files: FileList | File[]): Promise<void> {
  const candidates: AttachmentCandidate[] = [];
  for (const file of Array.from(files)) {
    try {
      const bytes = [...new Uint8Array(await file.arrayBuffer())];
      // A pasted screenshot arrives unnamed; give it something readable.
      const name = file.name && file.name !== "image.png"
        ? baseName(file.name)
        : `Pasted image ${stamp()}.png`;
      const written = await Bridge.ingestBytes(name, bytes);
      candidates.push({ path: written.path, byteCount: written.size });
    } catch (err) {
      State.replyNotice = String(err).replace(/^Error:\s*/, "");
      State.notify();
    }
  }
  attach(candidates);
}

/**
 * Opens the native picker.
 *
 * `pickingFile` holds the card open across it, for the same reason the Mac
 * does: the dialog takes focus, the input blurs, and without the flag the
 * auto-close timer would fold the card away behind the dialog and take the
 * draft with it.
 */
export async function pickFiles(): Promise<void> {
  State.pickingFile = true;
  State.notify();
  try {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const chosen = await open({ multiple: true, title: "Attach to your reply" });
    if (!chosen) return;
    await attachPaths(Array.isArray(chosen) ? chosen : [chosen]);
  } catch (err) {
    State.replyNotice = String(err).replace(/^Error:\s*/, "");
    State.notify();
  } finally {
    State.pickingFile = false;
    State.notify();
  }
}

export function remove(id: string): void {
  State.replyAttachments = State.replyAttachments.filter((a) => a.id !== id);
  if (State.replyAttachments.length === 0) State.replyNotice = null;
  State.notify();
}

/** Clears everything staged — on send, and on dismissing the card. */
export function clear(): void {
  if (State.replyAttachments.length === 0 && State.replyNotice === null
      && !State.replyDragOver) {
    return;
  }
  State.replyAttachments = [];
  State.replyNotice = null;
  State.replyDragOver = false;
  State.notify();
}

/** Whether a drop landing now should go to the reply rather than the bin. */
export function replyIsCatching(): boolean {
  const message = State.view === "message"
    ? State.activeMessage
    : State.view === "overview"
      ? State.homeMessage
      : null;
  if (!message?.conversationId) return false;
  // Mattermost can take files; ClickMassa has no upload route to aim at.
  return message.source === "mattermost";
}

export function paths(attachments: ReplyAttachment[]): string[] {
  return attachments.map((a) => a.path);
}

/** Seconds included: two pastes in the same minute are two files. */
function stamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    + ` at ${pad(d.getHours())}.${pad(d.getMinutes())}.${pad(d.getSeconds())}`;
}
