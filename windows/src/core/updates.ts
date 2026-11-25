// The island's side of the updater: what the update card says, and when it
// opens by itself.
//
// Rust owns the updater (src-tauri/src/update.rs) and broadcasts every change as
// "update-state" to every window. The settings window draws its Updates group
// from it; this is the same feed, read for the notch. The Mac twin is
// `Updater.offer` / `deferred` in Updater.swift.
//
// The one difference from the Mac is platform-forced: Sparkle downloads a new
// version in the background before the card appears, so the Mac's click goes
// straight to "Restarting…"; Tauri's updater downloads on the click, so this
// card has a "Downloading…" state with a bar between the two.

import { Bridge, IS_TAURI, onEvent, type UpdateState } from "./bridge";

/** What the card is saying. */
export type UpdateOffer =
  /** A version is out and this copy can install it: Update now / Later. */
  | { kind: "available"; version: string }
  /** It is out, but this copy cannot replace itself — the portable .zip, a
   *  .deb or .rpm, or a build carrying a replaced signing key. */
  | { kind: "manual"; version: string; url: string }
  | { kind: "downloading"; version: string; progress: number }
  /** Installed; the app is restarting into it. */
  | { kind: "restarting"; version: string }
  /** The download or the install failed. */
  | { kind: "failed"; version: string; error: string; url: string };

class UpdatesStore {
  /** This copy's version, from boot — the left side of "0.1.28 → 0.1.29". */
  current = "";
  offer: UpdateOffer | null = null;
  /** Answered with Later: the card stops opening by itself, and opening the
   *  island by hand finds Home again. Settings and the tray keep the offer. */
  deferred = false;

  /** Set by main.ts: a version nobody has been told about yet is out. */
  onOffered: (() => void) | null = null;

  private listeners = new Set<() => void>();

  subscribe(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  /** Whether opening the island by hand should land on the card. */
  get awaitsAnswer(): boolean {
    return this.offer !== null && !this.deferred;
  }

  async load(): Promise<void> {
    if (!IS_TAURI) return;
    await onEvent<UpdateState>("update-state", (next) => this.apply(next));
    try {
      const now = await Bridge.updateState();
      if (now) this.apply(now);
    } catch {
      // No state yet is the same as nothing on offer.
    }
  }

  /** The card's Update now. */
  install(): void {
    const offer = this.offer;
    if (!offer) return;
    if (offer.kind === "manual" || offer.kind === "failed") {
      void Bridge.openUrl(offer.url);
      return;
    }
    if (offer.kind === "available") void Bridge.updateInstall();
  }

  /** The card's Later. */
  later(): void {
    this.deferred = true;
    this.emit();
  }

  /** For the preview harness: say something without asking Rust. */
  seed(offer: UpdateOffer | null): void {
    this.offer = offer;
    this.deferred = false;
    this.emit();
  }

  private apply(state: UpdateState): void {
    const before = this.offer;
    const next = offerFrom(state, before);
    this.offer = next;
    // A version is news once. The hourly check finding the same release again
    // re-sends the same state, and must not reopen a card somebody closed.
    const news = next !== null && next.version !== before?.version
      && (next.kind === "available" || next.kind === "manual");
    if (news) this.deferred = false;
    this.emit();
    if (news) this.onOffered?.();
  }

  private emit() {
    for (const fn of this.listeners) fn();
  }
}

/**
 * Reads Rust's state as the card's. `previous` fills in what a passing state
 * leaves out: a check under way says nothing about the release already on
 * offer, and a failure resets the version to none.
 */
export function offerFrom(state: UpdateState, previous: UpdateOffer | null): UpdateOffer | null {
  const version = state.version ?? previous?.version ?? null;
  switch (state.phase) {
    case "available":
      if (!version) return null;
      return state.installable
        ? { kind: "available", version }
        : { kind: "manual", version, url: state.releaseUrl };
    case "downloading":
      return version ? { kind: "downloading", version, progress: state.progress } : previous;
    case "ready":
      return version ? { kind: "restarting", version } : previous;
    case "error":
      // Only a failure of something the card started is the card's business;
      // a check that failed is Settings'.
      if (previous && (previous.kind === "downloading" || previous.kind === "restarting")) {
        return { kind: "failed", version: previous.version, error: state.error ?? "", url: state.releaseUrl };
      }
      return previous;
    case "checking":
      return previous;
    case "idle":
    case "upToDate":
      return null;
  }
}

export const Updates = new UpdatesStore();
