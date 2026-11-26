// The message pop-up — the card Mattermost and Ato messages land in.
//
// Atoll's behaviour is the specification: who it is from on the first line, the
// message under it, a reply field on the left and Open on the far right. Return
// sends and the card goes; Escape waves it away. While the field has the cursor
// the island is pinned, because a card that slid away on its own timer would
// take a half-written sentence with it.
//
// One card for both sources, like MessageEvent is one shape for both: the only
// thing that varies is the accent colour and what the ↗ points at.

import { h, svg, clear, dot, measureBodyHeight } from "./dom";
import { ICONS } from "./icons";
import { btn, card, stack, type ViewActions, type ViewHost } from "./views";
import { State, SOURCE_COLOR, SOURCE_LABEL, homeSource, type InboxMessage } from "../core/state";
import { replyToMessage } from "../island/messages";
import * as ReplyAttachments from "../island/replyAttachments";
import * as VoiceNote from "../island/voiceNote";
import * as VoicePlayer from "../island/voicePlayer";
import { skipIcon } from "./nowplaying";
import { sizeLabel } from "../core/attachments";
import {
  MESSAGE_BODY_TWO_LINES, PHOTO_CAPTION_GAP, VOICE_GAP, VOICE_PLAYER_HEIGHT,
  photoColumnWidth, photoDisplaySize,
} from "../core/layout";
import * as InboxPhoto from "../island/inboxPhoto";
import * as MessageCopy from "../island/messageCopy";
import { t } from "../core/i18n";

/**
 * How long ago, as the card and the list say it — the Swift `timeAgo`
 * computed properties. Lived with the integration cards until they went.
 */
export function timeAgo(value: unknown): string {
  const date = typeof value === "number" ? new Date(value) : new Date(String(value));
  const diff = (Date.now() - date.getTime()) / 1000;
  if (!Number.isFinite(diff)) return "";
  if (diff < 60) return "just now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
}

/** Who it is from, where it came from, and how long ago. */
function whoRow(message: InboxMessage, others: number): Node[] {
  const accent = SOURCE_COLOR[message.source];
  const where = message.channel
    ? `in ${message.channel}`
    : `${SOURCE_LABEL[message.source]} · direct`;
  const age = timeAgo(message.timestampMs);
  return [
    dot(accent, 8),
    h("span", { class: "n", text: message.sender || SOURCE_LABEL[message.source] }),
    h("span", { text: where }),
    h("span", {
      style: "margin-left:auto;flex:0 0 auto;font:400 11px var(--font);color:var(--dim-3)",
      text: others > 0 ? `${others} more waiting · ${age}` : age,
    }),
  ];
}

/**
 * @param home Built for the Home tab rather than as the notification pop-up.
 *
 * The difference is which message, and that is the point. The pop-up shows
 * `State.activeMessage` — the newest **unread** — so it empties the moment you
 * answer. Home shows the newest from its source whether or not it has been
 * read, so the notification is still here when you come back to it after the
 * card has folded away. Home also never takes itself off screen: you opened it.
 */
export function buildMessage(actions: ViewActions, home = false): ViewHost {
  const who = h("div", { class: "who-row", style: "flex:0 0 auto" });
  // Two lines, then an ellipsis. The card is a fixed 160 and the three rows
  // fill it exactly, so each one refuses to be squeezed: letting the body
  // shrink instead clipped its second line in half.
  const CLAMPED =
    "flex:0 0 auto;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;"
    + "overflow:hidden;line-height:1.35;height:36px;white-space:pre-wrap;word-break:break-word";
  // The whole message, in the shape `.msg-list` already uses to scroll inside
  // the island. `0 1 auto`, never `1 1`: the card has been sized to hold this
  // exactly — by the same measurement, in `island.bodyOverflow` — so the body
  // takes the room the text needs and no more, and the shrink is what makes it
  // scroll once the card has stopped growing at `MESSAGE_EXPANDED_CAP`. The
  // floor is the two lines the card has always kept, so one line draws the
  // card it draws with the preference off.
  const FULL =
    `flex:0 1 auto;min-height:${MESSAGE_BODY_TWO_LINES}px;overflow-y:auto;line-height:1.35;`
    + "white-space:pre-wrap;word-break:break-word;"
    + "scrollbar-width:thin;scrollbar-color:rgba(255,255,255,0.18) transparent";
  const body = h("div", { class: "sub", style: CLAMPED });
  // A photo's caption at rest: up to two lines, and only as tall as it is —
  // the card was grown by its measured height, not by a fixed two lines.
  const CLAMPED_CAPTION =
    "flex:0 0 auto;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;"
    + `overflow:hidden;line-height:1.35;max-height:${MESSAGE_BODY_TWO_LINES}px;`
    + "white-space:pre-wrap;word-break:break-word";

  // ── A received voice message ──────────────────────────────────────────────
  //
  // Takes the body's place: the player held still in a row of its own, and
  // what was said under it in a box that scrolls — so a long transcript is
  // read by scrolling rather than by pushing the player and the reply bar
  // off the card. The Now Playing card's controls, at card-row size.
  const voiceBack = h("button", { class: "np-btn vn-skip" });
  const voiceFwd = h("button", { class: "np-btn vn-skip" });
  const voicePlay = h("button", { class: "vn-play" });
  const voiceFill = h("div", { class: "np-fill" });
  const voiceThumb = h("div", { class: "vn-thumb" });
  const voiceBar = h("div", { class: "np-bar vn-bar" }, voiceFill, voiceThumb);
  const voiceNow = h("span", { class: "vn-time" });
  const voiceLabel = h("span", { class: "vn-label" });
  const voiceTotal = h("span", { class: "vn-time" });
  const voiceTimes = h("div", { class: "vn-times" }, voiceNow, voiceLabel, voiceTotal);
  const voiceTrack = h("div", { class: "vn-track" }, voiceBar, voiceTimes);
  const voicePlayer = h("div", {
    class: "vn-player", style: `height:${VOICE_PLAYER_HEIGHT}px`,
  }, voiceBack, voicePlay, voiceFwd, voiceTrack);
  const transcript = h("div", { class: "sub vn-transcript" });
  const voice = h("div", {
    class: "vn", style: `display:none;gap:${VOICE_GAP}px`,
  }, voicePlayer, transcript);

  /** The clip on the card, by its storage id. */
  let voiceId: string | null = null;
  /** Ato's own measure, until the clip itself is here. */
  let voiceDuration = 0;
  /** Where the thumb is while being dragged, as a fraction of the clip. */
  let scrubbing: number | null = null;
  /** Whether listening was holding the card at the last sync. */
  let wasListening = false;

  voicePlay.addEventListener("click", () => {
    if (voiceId) VoicePlayer.toggle(voiceId);
  });
  voiceBack.addEventListener("click", () => {
    if (voiceId) VoicePlayer.skip(voiceId, -State.settings.skipBackSeconds);
  });
  voiceFwd.addEventListener("click", () => {
    if (voiceId) VoicePlayer.skip(voiceId, State.settings.skipForwardSeconds);
  });

  function fractionAt(event: PointerEvent): number {
    const box = voiceBar.getBoundingClientRect();
    if (box.width <= 0) return 0;
    return Math.min(Math.max((event.clientX - box.left) / box.width, 0), 1);
  }
  // Dragging the bar: the thumb follows the pointer and the clip is told
  // where to go on release — the Now Playing card's scrubber.
  voiceBar.addEventListener("pointerdown", (event) => {
    try {
      voiceBar.setPointerCapture(event.pointerId);
    } catch {
      /* not capturable — dragging still works while the pointer is over it */
    }
    scrubbing = fractionAt(event);
    paintVoiceClock();
  });
  voiceBar.addEventListener("pointermove", (event) => {
    if (scrubbing == null) return;
    scrubbing = fractionAt(event);
    paintVoiceClock();
  });
  const releaseBar = (event: PointerEvent) => {
    if (scrubbing == null || !voiceId) return;
    VoicePlayer.seek(voiceId, fractionAt(event));
    // A clip still loading takes the position when it arrives; until then
    // the thumb stays where it was let go.
    if (VoicePlayer.loaded(voiceId)) scrubbing = null;
    paintVoiceClock();
  };
  voiceBar.addEventListener("pointerup", releaseBar);
  voiceBar.addEventListener("pointercancel", releaseBar);

  function voiceLength(): number {
    if (voiceId && VoicePlayer.loaded(voiceId)) {
      const own = VoicePlayer.length();
      if (Number.isFinite(own) && own > 0) return own;
    }
    return voiceDuration;
  }

  /** The bar and the left-hand time: the only things a frame can move. */
  function paintVoiceClock() {
    if (!voiceId) return;
    const total = voiceLength();
    const at = VoicePlayer.loaded(voiceId) ? VoicePlayer.position() : 0;
    const fraction = scrubbing ?? (total > 0 ? Math.min(Math.max(at / total, 0), 1) : 0);
    voiceFill.style.width = `${fraction * 100}%`;
    voiceThumb.style.left = `${fraction * 100}%`;
    voiceThumb.style.opacity = VoicePlayer.loaded(voiceId) || scrubbing != null ? "1" : "0";
    voiceNow.textContent = clock(scrubbing != null ? scrubbing * total : at);
    voiceTotal.textContent = total > 0 ? clock(total) : "–:––";
  }

  function syncVoice(message: InboxMessage, problem: string | null): boolean {
    const audio = message.audio;
    if (!audio || problem) {
      voice.style.display = "none";
      voiceId = null;
      return false;
    }
    voice.style.display = "flex";
    if (voiceId !== audio.storageFileId) scrubbing = null;
    voiceId = audio.storageFileId;
    voiceDuration = audio.durationSeconds ?? 0;

    const full = State.settings.messageFullBody;
    // Two lines of transcript at rest; as much as the island allows when the
    // card may grow, past which it scrolls.
    voice.style.flex = full ? "0 1 auto" : "0 0 auto";
    voice.style.minHeight = full ? "0" : "";
    transcript.style.flex = full ? "0 1 auto" : "0 0 auto";
    transcript.style.height = full ? "" : `${MESSAGE_BODY_TWO_LINES}px`;
    transcript.style.minHeight = `${MESSAGE_BODY_TWO_LINES}px`;

    const isPlaying = VoicePlayer.playing(voiceId);
    const isLoading = VoicePlayer.loading(voiceId);
    clear(voicePlay);
    voicePlay.append(isLoading
      ? h("i", { class: "vn-spinner" })
      : svg(isPlaying ? ICONS.pause : ICONS.play, 14));
    voicePlay.classList.toggle("on", isPlaying);
    voicePlay.title = isPlaying ? t("Pause") : t("Play");

    const back = State.settings.skipBackSeconds;
    const fwd = State.settings.skipForwardSeconds;
    clear(voiceBack);
    voiceBack.append(skipIcon(back, false, 16));
    voiceBack.title = `Back ${back}s`;
    clear(voiceFwd);
    voiceFwd.append(skipIcon(fwd, true, 16));
    voiceFwd.title = `Forward ${fwd}s`;

    const broken = VoicePlayer.failed(voiceId);
    voiceLabel.classList.toggle("bad", broken);
    voiceLabel.textContent = broken ? t("Couldn't load the audio") : t("Voice message");

    transcript.classList.toggle("quiet", audio.transcriptStatus !== "ready");
    copyable(transcript);
    copyable(voiceTimes);
    transcript.textContent =
      audio.transcriptStatus === "ready" ? audio.transcript ?? ""
      : audio.transcriptStatus === "pending" ? t("Transcribing…")
      : audio.transcriptStatus === "failed" ? t("No transcript for this one")
      : "";
    paintVoiceClock();
    return true;
  }

  // ── A received photo ──────────────────────────────────────────────────────
  //
  // Takes the body's place, at the size `island.bodyOverflow` grew the card
  // by: the photo, and what was written with it under it. A click opens the
  // original in the system's viewer — `InboxPhotoView` on the Mac. The frame
  // spans the card's whole width, so its edges line up with the caption and
  // the reply bar; a narrower photo sits in the middle over a blurred copy.
  const photoImg = h("img", { class: "ph-img", alt: "", draggable: "false" }) as HTMLImageElement;
  // What fills the frame either side of a photo narrower than the card: the
  // photo itself, or the server's thumbnail until it is here, blurred.
  const photoBack = h("img", { class: "ph-back", alt: "", draggable: "false" }) as HTMLImageElement;
  const photoNote = h("div", { class: "ph-note" });
  const photoSpin = h("i", { class: "vn-spinner ph-spin" });
  const photoZoom = h("span", { class: "ph-badge ph-zoom", title: t("See it full size") });
  const photoMore = h("span", { class: "ph-badge ph-more" });
  const photoFoot = h("div", { class: "ph-foot" });
  const photoFrame = h("button", { class: "ph-frame", title: t("Click to see it full size") },
                       photoBack, photoImg, photoNote, photoSpin, photoZoom, photoMore, photoFoot);
  const photoCaption = h("div", { class: "sub ph-caption" });
  const photoBox = h("div", {
    class: "ph", style: `display:none;gap:${PHOTO_CAPTION_GAP}px`,
  }, photoFrame, photoCaption);

  /** The photo on the card, so a click and a broken image know which. */
  let shownPhoto: InboxMessage["photo"] = null;

  // A click on the photo copies the message when there is something to copy,
  // and seeing it whole moves to the enlarge mark in its corner — the Mac's
  // `InboxPhotoView` with `onCopy`. With nothing to copy it opens, as before.
  photoFrame.addEventListener("click", (event) => {
    if (!shownPhoto) return;
    const onMark = (event.target as Element | null)?.closest(".ph-zoom") != null;
    if (copyOnClick && !onMark) copyCurrent();
    else InboxPhoto.open(shownPhoto);
  });
  photoImg.addEventListener("error", () => {
    if (shownPhoto && photoImg.getAttribute("src")) InboxPhoto.markBroken(shownPhoto.fileId);
  });

  function syncPhoto(message: InboxMessage, problem: string | null): boolean {
    const photo = message.photo ?? null;
    shownPhoto = photo;
    if (!photo) {
      photoBox.style.display = "none";
      return false;
    }
    photoBox.style.display = "flex";
    const width = photoColumnWidth(State.settings.hideCharacters);
    const size = photoDisplaySize(photo.pixelWidth, photo.pixelHeight, width);
    photoFrame.style.width = `${width}px`;
    photoFrame.style.height = `${size.h}px`;
    photoImg.style.width = `${size.w}px`;
    photoImg.style.height = `${size.h}px`;

    const url = InboxPhoto.url(photo.fileId);
    if (url) {
      if (photoImg.getAttribute("src") !== url) photoImg.src = url;
      photoImg.style.display = "";
    } else {
      photoImg.removeAttribute("src");
      photoImg.style.display = "none";
    }
    const mini = photo.miniPreview ? `data:image/jpeg;base64,${photo.miniPreview}` : null;
    // Behind a photo that fills the width there is nothing to fill.
    const back = url ? (size.w < width ? InboxPhoto.stillUrl(photo.fileId) : null) : mini;
    if (back) {
      if (photoBack.getAttribute("src") !== back) photoBack.src = back;
      photoBack.style.display = "";
      photoBack.classList.toggle("mini", !url);
    } else {
      photoBack.removeAttribute("src");
      photoBack.style.display = "none";
    }

    const broken = InboxPhoto.failed(photo.fileId);
    const placeholder = !url && (broken || !InboxPhoto.canShowInline(photo));
    photoNote.style.display = placeholder ? "" : "none";
    if (placeholder) {
      clear(photoNote);
      photoNote.append(svg(ICONS.photo, 20),
                       h("span", {
                         text: broken ? t("Couldn't load the photo")
                           : copyOnClick ? t("Click to copy") : t("Click to see it full size"),
                       }));
    }
    photoFrame.title = copyOnClick ? t("Click to copy") : t("Click to see it full size");
    // With nothing drawn to copy from, the way to see it whole stays in view.
    photoZoom.classList.toggle("shown", copyOnClick && placeholder);
    photoSpin.style.display = !url && !placeholder ? "" : "none";

    const opening = InboxPhoto.isOpening(photo.fileId);
    photoZoom.classList.toggle("busy", opening);
    clear(photoZoom);
    photoZoom.append(opening ? h("i", { class: "vn-spinner light" }) : svg(ICONS.expand, 10));
    photoMore.style.display = photo.more > 0 ? "" : "none";
    photoMore.textContent = `+${photo.more}`;

    // A failed reply is said over the foot of the photo, so the card does not
    // change height to say it.
    const foot = problem ?? InboxPhoto.openFailure(photo.fileId);
    photoFoot.style.display = foot ? "" : "none";
    photoFoot.textContent = foot ?? "";

    // No taller than the caption itself, even when the card may grow:
    // stretching to fill it would push the rows above up against the header.
    // It only scrolls once the card has hit its cap.
    const full = State.settings.messageFullBody;
    photoCaption.textContent = photo.caption ?? "";
    photoCaption.setAttribute(
      "style",
      !photo.caption ? "display:none"
        : full ? `${FULL};min-height:0;max-height:${measureBodyHeight(photo.caption, width)}px`
          : CLAMPED_CAPTION,
    );
    copyable(photoCaption);
    return true;
  }

  // ── Click to copy ─────────────────────────────────────────────────────────
  //
  // A click on the message itself — its words, its photo, its voice message —
  // copies it, the same as Copy beside Open: "clicou, copiou". Not while the
  // body is saying what went wrong, which is not the message. The Mac's
  // `copiesOnClick`.

  /** Whether a click on the message copies it, as of the last sync. */
  let copyOnClick = false;

  function copyCurrent() {
    const message = current();
    if (message && copyOnClick) MessageCopy.copy(message);
  }

  /** Marks `el` as a place a click copies — or not — and says so on hover. */
  function copyable(el: HTMLElement) {
    el.classList.toggle("copyable", copyOnClick);
    if (copyOnClick) el.title = t("Click to copy");
    else el.removeAttribute("title");
  }

  body.addEventListener("click", copyCurrent);
  photoCaption.addEventListener("click", copyCurrent);
  transcript.addEventListener("click", copyCurrent);
  voiceTimes.addEventListener("click", copyCurrent);

  const input = h("input", {
    type: "text",
    class: "chat-input",
    placeholder: t("Reply…"),
    spellcheck: "false",
    autocomplete: "off",
  }) as HTMLInputElement;
  // A notch shorter than the chat's: three rows have to fit inside 160.
  const send = h("button", {
    class: "send-btn", title: t("Send"), style: "width:24px;height:24px;flex:0 0 24px",
  }, svg(ICONS.arrowUp, 11));
  // Lives inside the bar rather than above it, so the card needs no extra row
  // until a file is actually attached.
  const clip = h("button", {
    class: "clip-btn", title: t("Attach files"), style: "flex:0 0 auto",
  }, svg(ICONS.paperclip, 12));
  // Beside the paperclip: both are "something other than words", and both go
  // away together for a source that cannot carry one.
  const mic = h("button", {
    class: "clip-btn mic-btn", title: t("Record a voice message"), style: "flex:0 0 auto",
  }, svg(ICONS.mic, 13));
  // What the bar shows instead of the field while recording. Nothing is staged
  // yet, so the card is still its plain height and there is no row to grow into.
  const micTime = h("span", { class: "mic-time", text: "0:00" });
  const scrap = h("button", { class: "clip-btn", title: t("Discard recording") },
                  svg(ICONS.xmark, 11));
  const micRow = h("div", { class: "mic-row" },
                   h("i", { class: "mic-level" }), micTime, scrap);
  const bar = h("div", { class: "chat-bar", style: "flex:1 1 auto;min-width:0" },
                clip, mic, input, micRow, send);

  mic.addEventListener("click", () => {
    if (VoiceNote.isRecording()) {
      void VoiceNote.stop().then(() => actions.setPinned(false));
      return;
    }
    // Pinned the way the field pins on focus, and for the same reason: a
    // click is not a focus, so without this the card folds away mid-sentence.
    actions.setPinned(true);
    void VoiceNote.start();
  });
  scrap.addEventListener("click", () => {
    VoiceNote.cancel();
    actions.setPinned(false);
  });
  // Copy: what the sender sent, on the clipboard — `CopyMessageButton` on the
  // Mac. Every face sits in the same grid cell and only one is visible, so
  // the button is as wide as its widest face and the bar beside it does not
  // twitch when "Copy" turns into "Copied".
  const copyIdle = h("span", { class: "copy-face", text: t("Copy") });
  const copyDone = h("span", { class: "copy-face copy-done" },
                     svg(ICONS.check, 10, { stroke: 2.6 }), h("span", { text: t("Copied") }));
  const copySpin = h("span", { class: "copy-face" }, h("i", { class: "vn-spinner light copy-spin" }));
  const copy = h("button", {
    class: "btn secondary copy-btn", title: t("Copy exactly what was sent, to paste anywhere"),
  }, copyIdle, copyDone, copySpin);
  copy.addEventListener("click", () => {
    const message = current();
    if (message) MessageCopy.copy(message);
  });
  const open = btn("Open", "secondary", () => openCurrent());
  const row = h("div", { class: "actions", style: "flex:0 0 auto;align-items:center" }, bar, copy, open);

  // Only shown once something is staged, so a text-only reply is the
  // three-row card it has always been.
  const chips = h("div", { class: "chip-row", style: "flex:0 0 auto;display:none" });
  const notice = h("div", { class: "chip-notice", style: "flex:0 0 auto;display:none" });

  // The pop-up is tinted by whoever wrote; Home draws its own background, like
  // every other thing Home can hold.
  const cardEl = card(home ? null : "indigo", stack(116, 16, who, body, voice, photoBox, chips, notice, row));
  const el = h("div", { class: "view" }, cardEl);

  // ── Where copying stands, beside what was clicked ─────────────────────────
  //
  // "✓ Copied" at the right of the words, the photo or the voice message's
  // transcript for a moment after a copy, and a spinner while the photo or
  // the audio is still coming — `CopyStatusBadge` on the Mac. One badge for
  // the card, laid over it where the thing clicked is.
  const statusSpin = h("i", { class: "vn-spinner light cs-spin" });
  const statusCheck = h("span", { class: "cs-check" }, svg(ICONS.check, 10, { stroke: 2.8 }));
  const statusText = h("span", { class: "cs-text" });
  const copyStatus = h("div", { class: "copy-status" }, statusSpin, statusCheck, statusText);
  cardEl.append(copyStatus);

  /** Between the end of the words and the badge — `CopyStatusBadge.gap`. */
  const STATUS_GAP = 8;

  /**
   * Puts the badge over `target`'s top right corner, `inset` in from it and
   * `lift` up — half of what the badge is taller than a line of text, so
   * beside words it sits level with the first line. Null puts it away.
   *
   * With `words`, the badge goes right after them instead when they are one
   * line with room left on it — next to "Oi" rather than across the card from
   * it — the Mac's `copyStatus(_:beside:lift:)`.
   */
  function placeCopyStatus(message: InboxMessage, target: HTMLElement | null, inset: number, lift: number,
                           words = false) {
    const busy = MessageCopy.copying(message.id);
    const done = !busy && MessageCopy.copied(message.id);
    const on = target != null && (busy || done);
    copyStatus.classList.toggle("on", on);
    photoZoom.classList.toggle("hold", on && target === photoFrame);
    if (!on || !target) return;
    copyStatus.classList.toggle("busy", busy);
    statusText.textContent = t("Copied");
    const frame = cardEl.getBoundingClientRect();
    const box = target.getBoundingClientRect();
    copyStatus.style.top = `${box.top - frame.top - cardEl.clientTop + inset - lift}px`;
    const end = words ? oneLineEnd(target) : null;
    if (end != null && end + STATUS_GAP + copyStatus.offsetWidth <= box.right) {
      copyStatus.style.left = `${end + STATUS_GAP - frame.left - cardEl.clientLeft}px`;
      copyStatus.style.right = "";
      copyStatus.style.transformOrigin = "left center";
    } else {
      copyStatus.style.left = "";
      copyStatus.style.right = `${frame.right - box.right - cardEl.clientLeft + inset}px`;
      copyStatus.style.transformOrigin = "";
    }
  }

  /** Where `el`'s words end on screen, when they are a single line; null otherwise. */
  function oneLineEnd(el: HTMLElement): number | null {
    const text = el.textContent ?? "";
    if (!text || /\n/.test(text)) return null;
    const range = document.createRange();
    range.selectNodeContents(el);
    const lines = new Set([...range.getClientRects()].map((r) => Math.round(r.top)));
    if (lines.size !== 1) return null;
    return Math.ceil(range.getBoundingClientRect().right);
  }

  /** The id the fields were last reset for, so typing survives a re-sync. */
  let shownId: string | null = null;
  let sending = false;
  let error: string | null = null;

  function current(): InboxMessage | null {
    return home ? State.homeMessage : State.activeMessage;
  }

  /**
   * Done with `message`: mark it read and show the next one, or go home.
   *
   * Handed the message rather than reading the card again. A reply takes a
   * moment to go, and in that moment another can take the card — one that
   * arrives while the field is disabled, or Home's newest from the same
   * source — and reading it then marked that one read and left the one
   * answered unread. The Mac marks the message it replied to
   * (`MessageInbox.reply(to:)`).
   */
  function dismiss(message: InboxMessage | null) {
    VoicePlayer.stop();
    VoiceNote.cancel();
    VoiceNote.releaseClips();
    ReplyAttachments.clear();
    if (message) State.dismissMessage(message.id);
    input.value = "";
    error = null;
    sending = false;
    // Home stays. Taking the tab away after a reply would undo the whole reason
    // Home holds the last message in the first place.
    if (home) return;

    // Where this goes next is the card's to say only while it is still the
    // card on screen. A reply takes a moment to go, and in that moment the user
    // may have gone somewhere else — a tab, ChatGPT, the site — and whatever
    // they went to stays: the Mac's `.islandCollapse` is refused the same way
    // while a screen holds the island. The bookkeeping above, and the list's
    // below, happen either way.
    const onScreen = State.mode === "expanded" && State.view === "message";

    // Answered from a list: that list owns where this goes next. Falling
    // through would hand on to whatever else is unread, which for someone
    // working through Ato means a Mattermost card out of nowhere.
    const source = State.listSource;
    if (source) {
      input.blur();
      // "all" is the Notifications queue: it owns both services, so what
      // decides whether to go back to it is everything still unanswered.
      const left = source === "all" ? State.unreadAllList() : State.unreadList(source);
      if (left.length > 0) {
        if (onScreen) actions.setView("messages");
      } else {
        State.closeMessageList();
        if (onScreen) actions.setView(State.defaultView());
      }
      return;
    }

    const more = State.unreadMessages.length > 0;
    // Keep the cursor — and with it the pin — only while there is another card
    // to answer here. Letting go anywhere else would leave the island pinned
    // open on a field nobody can see.
    if (!more || !onScreen) input.blur();
    if (onScreen) actions.setView(more ? "message" : State.defaultView());
  }

  function openCurrent() {
    const message = current();
    if (message?.link) actions.openUrl(message.link);
    dismiss(message);
  }

  async function submit() {
    const message = current();
    const text = input.value.trim();
    const attachments = State.replyAttachments;
    // Words or files; neither alone is required, but one of them is.
    if (!message || (!text && attachments.length === 0) || sending) return;
    if (!message.conversationId) {
      error = t("There is nowhere to reply to this one.");
      State.notify();
      return;
    }
    sending = true;
    error = null;
    State.notify();
    try {
      await replyToMessage(message, text, ReplyAttachments.paths(attachments));
      input.value = "";
      // The clips and the chips go in `dismiss()`, two lines down.
      sending = false;
      dismiss(message);
    } catch (err) {
      // The card says what went wrong and keeps what was typed: a reply that
      // vanished with the error would have to be written twice.
      sending = false;
      error = String(err).replace(/^Error:\s*/, "");
      State.notify();
    }
  }

  /** What an empty card says — named by its source when Home has one. */
  function emptyLine(): string {
    if (!home) return t("Nothing waiting.");
    const source = homeSource(State.settings.homeContent, State.lastSource);
    if (source === "ato") return "Nothing from Ato yet.";
    if (source === "mattermost") return "Nothing from Mattermost yet.";
    if (source === "whatsapp") return "Nothing from WhatsApp yet.";
    return "No messages yet.";
  }

  send.addEventListener("click", () => void submit());
  clip.addEventListener("click", () => void ReplyAttachments.pickFiles());

  // Tauri intercepts OS *drops* before the webview sees them, but not pastes —
  // so this is the one route a pasted screenshot can take. Plain text is left
  // alone and still reaches the field.
  input.addEventListener("paste", (e) => {
    const files = (e as ClipboardEvent).clipboardData?.files;
    if (!files || files.length === 0) return;
    if (!ReplyAttachments.replyIsCatching()) return;
    e.preventDefault();
    void ReplyAttachments.attachClipboardFiles(files);
  });

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      void submit();
    } else if (e.key === "Escape") {
      e.preventDefault();
      input.blur();
      if (!home) dismiss(current());
    }
    // The island closes on Escape too; handling it here means it closes once.
    e.stopPropagation();
  });

  // Clicking into the field is a request for the keyboard, and the window has to
  // be allowed to take it before the keystrokes can land — the island is created
  // non-activating precisely so a card arriving never does this on its own.
  // `mousedown` rather than `focus`: it runs before the field takes the caret.
  input.addEventListener("mousedown", () => void actions.focusField(true));
  input.addEventListener("focus", () => actions.setPinned(true));
  // Letting go of the caret is not yet letting go of the keyboard: the island
  // waits out the press that took it, and keeps the keyboard if that press
  // brought up ChatGPT, the site or the chat (`letFieldGo`).
  input.addEventListener("blur", () => {
    actions.setPinned(false);
    void actions.focusField(false);
  });

  return {
    el,
    sync() {
      const message = current();
      if (!message) {
        copyOnClick = false;
        copyable(body);
        copyStatus.classList.remove("on");
        who.replaceChildren(h("span", { text: emptyLine() }));
        body.textContent = "";
        voice.style.display = "none";
        voiceId = null;
        photoBox.style.display = "none";
        shownPhoto = null;
        row.style.display = "none";
        return;
      }
      row.style.display = "";

      if (message.id !== shownId) {
        // The clip belonged to the last card: nothing should go on playing
        // under someone else's message.
        if (shownId != null && voiceId && VoicePlayer.loaded(voiceId)) VoicePlayer.stop();
        shownId = message.id;
        input.value = "";
        error = null;
      }

      if (!home) cardEl.style.setProperty("--wash", `${SOURCE_COLOR[message.source]}8c`);

      const others = State.unreadMessages.filter((m) => m.id !== message.id).length;
      clear(who);
      for (const node of whoRow(message, others)) who.append(node);

      // A copy that failed says so where a failed reply does, for the same
      // reason: there is no room for a row of its own.
      const problem = error ?? MessageCopy.failureFor(message.id);
      copyOnClick = problem == null && MessageCopy.canCopy(message);
      body.setAttribute("style", State.settings.messageFullBody ? FULL : CLAMPED);
      body.textContent = problem ?? message.body;
      body.style.color = problem ? "var(--red-text)" : "";
      copyable(body);
      // A failed reply still takes the whole body, voice message or not: what
      // went wrong matters more than the message being answered. A photo is
      // the exception — the card is as tall as it is, so it stays and the
      // failure is said over its foot.
      const isVoice = syncVoice(message, problem);
      const isPhoto = !isVoice && syncPhoto(message, problem);
      if (isVoice || isPhoto) body.style.display = "none";
      if (problem) placeCopyStatus(message, null, 0, 0);
      else if (isPhoto) placeCopyStatus(message, photoFrame, 6, 0);
      // Beside a transcript only once there is one: "Transcribing…" is not
      // what was copied.
      else placeCopyStatus(message, isVoice ? transcript : body, 0, 2,
                           !isVoice || message.audio?.transcriptStatus === "ready");

      // Listening holds the card the way the field having the cursor does —
      // and keeps a new message from taking the card out from under it.
      // Only the view on screen decides: both cards are built and synced.
      if (State.view === (home ? "overview" : "message")) {
        const listening = VoicePlayer.busy();
        if (listening !== wasListening) {
          wasListening = listening;
          actions.setPinned(listening || document.activeElement === input);
        }
      }

      input.disabled = sending;
      input.placeholder = !message.conversationId
        ? t("No reply channel")
        : sending
          ? t("Sending…")
          : `Reply to ${message.sender || SOURCE_LABEL[message.source]}…`;
      send.style.opacity = sending ? "0.4" : "1";
      open.style.display = message.link ? "" : "none";

      copy.style.display = MessageCopy.canCopy(message) ? "" : "none";
      const busy = MessageCopy.copying(message.id);
      const done = !busy && MessageCopy.copied(message.id);
      copy.disabled = busy;
      copyIdle.classList.toggle("on", !busy && !done);
      copyDone.classList.toggle("on", done);
      copySpin.classList.toggle("on", busy);

      // Nothing for a source that cannot carry a file: a button that always
      // fails is worse than no button. Hiding rather than disabling, for the
      // microphone too — a webview with no capture at all offers nothing.
      const catching = ReplyAttachments.replyIsCatching();
      clip.style.display = catching ? "" : "none";
      mic.style.display = catching && VoiceNote.canRecord() ? "" : "none";

      const recording = VoiceNote.isRecording();
      bar.classList.toggle("recording", recording);
      mic.classList.toggle("on", recording);
      mic.title = recording ? t("Stop recording") : t("Record a voice message");
      clear(mic);
      mic.append(svg(recording ? ICONS.stop : ICONS.mic, recording ? 11 : 13));
      if (recording) {
        const total = Math.floor(VoiceNote.elapsed());
        micTime.textContent = `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
      }

      // A file hovering over an open reply says so here, rather than by
      // morphing Mochi into a bin and taking the card away.
      bar.classList.toggle("drop-target", State.replyDragOver);

      const staged = State.replyAttachments;
      chips.style.display = staged.length > 0 ? "" : "none";
      clear(chips);
      for (const attachment of staged) {
        const strip = h("button", {
          class: "chip-x", title: `Remove ${attachment.name}`,
        }, svg(ICONS.xmark, 8));
        strip.addEventListener("click", () => ReplyAttachments.remove(attachment.id));
        // The dot conveys nothing on every other chip. On a clip recorded
        // here it is the control — same 7 px slot, so a voice note joining a
        // row of files does not reflow it.
        const playable = VoiceNote.canPlay(attachment.path);
        let head: HTMLElement;
        if (playable) {
          const isPlaying = VoiceNote.playingPath() === attachment.path;
          head = h("button", { class: "chip-play", title: isPlaying ? t("Pause") : t("Play") },
                   svg(isPlaying ? ICONS.pause : ICONS.play, 8));
          head.addEventListener("click", () => VoiceNote.toggle(attachment.path));
        } else {
          head = h("span", { class: "chip-dot", "data-kind": attachment.kind });
        }
        chips.append(h("div", { class: "chip att-chip" },
          head,
          h("span", { class: "att-name", text: attachment.name }),
          h("span", { class: "att-size", text: sizeLabel(attachment.byteCount) }),
          strip));
      }

      notice.style.display = State.replyNotice ? "" : "none";
      notice.textContent = State.replyNotice ?? "";
    },
    focus() {
      input.focus();
      input.select();
    },
    tick() {
      if (voiceId && VoicePlayer.playing(voiceId)) paintVoiceClock();
    },
  };
}

/** `m:ss`. */
function clock(seconds: number): string {
  const total = Number.isFinite(seconds) && seconds > 0 ? Math.round(seconds) : 0;
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}
