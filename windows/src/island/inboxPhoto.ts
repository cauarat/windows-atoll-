// The photos the message cards are showing — the twin of `InboxPhotoStore` in
// InboxPhotoView.swift.
//
// Fetched once and kept for the few most recent as blob URLs: a card goes back
// and forth between messages, and fetching the same preview again each time
// would be slow and rude to the server. Asked for when the message arrives, so
// the photo is usually here by the time the island has finished opening.

import { Bridge, type MessagePhoto } from "../core/bridge";
import { State } from "../core/state";
import { t } from "../core/i18n";

/** The most fetched to show a photo the server made no preview of. */
const MAX_INLINE_BYTES = 25 * 1024 * 1024;
/** How many photos are kept; the oldest blob is let go past this. */
const KEPT = 8;

/** fileId → blob URL, oldest first. */
const urls = new Map<string, string>();
/**
 * fileId → its first frame, for a picture that moves: what the blurred
 * backdrop is drawn from, held still — the Mac blurs the first frame too, and
 * a blur redone on every frame is work for nothing.
 */
const stills = new Map<string, string>();
const loading = new Set<string>();
const failures = new Set<string>();
const opening = new Set<string>();
const openFailures = new Map<string, string>();

/**
 * Whether the card fetches anything at all. A photo with no preview is the
 * whole file, so past the limit it stays a placeholder the click still opens —
 * and HEIC is one WebView2 cannot draw, whatever its size.
 */
export function canShowInline(photo: MessagePhoto): boolean {
  if (photo.hasPreview) return true;
  if (/\.(heic|heif)$/i.test(photo.name) || /^image\/hei[cf]$/i.test(photo.mimeType)) return false;
  return photo.byteCount <= MAX_INLINE_BYTES;
}

/** A GIF, by its type or its name — `InboxPhoto.isGIF`. */
export function isGIF(photo: MessagePhoto): boolean {
  return /^image\/gif$/i.test(photo.mimeType) || /\.gif$/i.test(photo.name);
}

/**
 * Whether the card is drawn from the original rather than the server's
 * preview: when there is no preview, and for a GIF, whose preview is a still
 * JPEG of its first frame — one small enough is fetched whole, so that it
 * moves. `InboxPhoto.cardShowsOriginal`.
 */
export function cardShowsOriginal(photo: MessagePhoto): boolean {
  return !photo.hasPreview || (isGIF(photo) && photo.byteCount > 0 && photo.byteCount <= MAX_INLINE_BYTES);
}

export function url(fileId: string): string | null {
  return urls.get(fileId) ?? null;
}

/** What to blur behind the photo: its first frame when it moves, else itself. */
export function stillUrl(fileId: string): string | null {
  return stills.get(fileId) ?? urls.get(fileId) ?? null;
}

export function failed(fileId: string): boolean {
  return failures.has(fileId);
}

export function isOpening(fileId: string): boolean {
  return opening.has(fileId);
}

export function openFailure(fileId: string): string | null {
  return openFailures.get(fileId) ?? null;
}

/** The card's copy, unless it is here or on its way. Safe to call as often as anything likes. */
export function load(photo: MessagePhoto) {
  const id = photo.fileId;
  if (urls.has(id) || loading.has(id) || !canShowInline(photo)) return;
  loading.add(id);
  failures.delete(id);
  void Bridge.mattermostPhoto(id, !cardShowsOriginal(photo), photo.remoteUrl ?? null)
    .then(async (bytes) => {
      const blob = new Blob([bytes]);
      keep(id, URL.createObjectURL(blob), mayMove(bytes) ? await firstFrame(blob) : null);
    })
    .catch(() => {
      failures.add(id);
    })
    .finally(() => {
      loading.delete(id);
      State.notify();
    });
}

/** The image would not draw — a format the webview cannot decode. */
export function markBroken(fileId: string) {
  forget(fileId);
  if (failures.has(fileId)) return;
  failures.add(fileId);
  State.notify();
}

/** The original, in whatever the computer opens images with. */
export function open(photo: MessagePhoto) {
  const id = photo.fileId;
  if (opening.has(id)) return;
  opening.add(id);
  openFailures.delete(id);
  State.notify();
  void Bridge.mattermostOpenPhoto(id, photo.name, photo.mimeType, photo.remoteUrl ?? null)
    .catch(() => {
      openFailures.set(id, t("Couldn't open the photo"));
    })
    .finally(() => {
      opening.delete(id);
      State.notify();
    });
}

function keep(id: string, blob: string, still: string | null) {
  forget(id);
  urls.set(id, blob);
  if (still) stills.set(id, still);
  while (urls.size > KEPT) {
    forget(urls.keys().next().value as string);
  }
}

function forget(id: string) {
  for (const map of [urls, stills]) {
    const blob = map.get(id);
    if (blob) URL.revokeObjectURL(blob);
    map.delete(id);
  }
}

/** A GIF or a WebP by its first bytes — the two that usually move. */
function mayMove(bytes: ArrayBuffer): boolean {
  const head = new Uint8Array(bytes, 0, Math.min(12, bytes.byteLength));
  const ascii = (from: number, to: number) => String.fromCharCode(...head.subarray(from, to));
  return ascii(0, 4) === "GIF8" || (ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP");
}

/** The picture's first frame, as a blob URL of its own; null when it cannot be had. */
async function firstFrame(blob: Blob): Promise<string | null> {
  try {
    const frame = await createImageBitmap(blob);
    const canvas = document.createElement("canvas");
    canvas.width = frame.width;
    canvas.height = frame.height;
    canvas.getContext("2d")?.drawImage(frame, 0, 0);
    frame.close();
    const still = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/png"));
    return still ? URL.createObjectURL(still) : null;
  } catch {
    return null;
  }
}
