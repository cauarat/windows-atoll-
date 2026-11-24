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

export function url(fileId: string): string | null {
  return urls.get(fileId) ?? null;
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
  void Bridge.mattermostPhoto(id, photo.hasPreview)
    .then((bytes) => {
      keep(id, URL.createObjectURL(new Blob([bytes])));
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
  const blob = urls.get(fileId);
  if (blob) URL.revokeObjectURL(blob);
  urls.delete(fileId);
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
  void Bridge.mattermostOpenPhoto(id, photo.name, photo.mimeType)
    .catch(() => {
      openFailures.set(id, t("Couldn't open the photo"));
    })
    .finally(() => {
      opening.delete(id);
      State.notify();
    });
}

function keep(id: string, blob: string) {
  urls.delete(id);
  urls.set(id, blob);
  while (urls.size > KEPT) {
    const [oldest, stale] = urls.entries().next().value as [string, string];
    URL.revokeObjectURL(stale);
    urls.delete(oldest);
  }
}
