// Stand-in for @tauri-apps/api/core on the download page.
//
// Every command the island would send to Rust lands here and gets the answer
// the app would give — the boot info of a MacBook with a notch, messages that
// send, a clipboard, music that plays — so the island's own code runs
// unchanged. Anything not listed answers null, which the bridge already treats
// as "not available".

import { emitLocal } from "./event";
import { pageShow, pageHide, pageOpenInBrowser } from "./pages";
import { SCENE, SAVED_KEY, MEDIA, demoSettings, meetings, clipboard, media, S } from "../data";
import type { BootInfo, MediaState } from "../../src/core/bridge";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

let mediaState: MediaState | null = null;
let mediaTimer: number | undefined;
let volume = { level: 0.6, muted: false };

export function startMedia() {
  mediaState = media();
  emitLocal("media", mediaState);
  window.clearInterval(mediaTimer);
  mediaTimer = window.setInterval(() => {
    if (!mediaState?.isPlaying) return;
    mediaState = { ...mediaState, elapsed: (mediaState.elapsed + 1) % mediaState.duration };
    emitLocal("media", mediaState);
  }, 1000);
}

/** Whatever opens something outside the island: the page around it says so. */
function outside(what: string) {
  window.parent?.postMessage({ type: "notchy-demo-outside", what }, "*");
}

// ── The clipboard window ────────────────────────────────────────────────────
// In the app it is a window of its own beside the island; here, the same page
// in a frame laid over the island's page.
const IN_CLIPBOARD = location.pathname.endsWith("clipboard.html");
let clipEntries = IN_CLIPBOARD ? clipboard() : [];
let clipFrame: HTMLIFrameElement | null = null;
function closeClip() {
  clipFrame?.remove();
  clipFrame = null;
}
function toggleClip() {
  if (clipFrame) return closeClip();
  clipFrame = document.createElement("iframe");
  clipFrame.src = new URL("./clipboard.html", location.href).href;
  clipFrame.title = "Clipboard";
  clipFrame.setAttribute("allow", "clipboard-write");
  Object.assign(clipFrame.style, {
    position: "fixed", top: "50px", left: "50%", width: "380px", height: "460px",
    transform: "translateX(-50%)", border: "0", zIndex: "50", background: "transparent",
    colorScheme: "dark",
  });
  document.body.append(clipFrame);
}
if (!IN_CLIPBOARD) {
  window.addEventListener("message", (e) => { if (e.data?.type === "notchy-clip-close") closeClip(); });
}

const photos = new Map<string, string>();
export function registerPhoto(fileId: string, url: string) {
  photos.set(fileId, url);
}
/** A sample's file: "photo-site#3" is media/photo-site.*. */
const mediaUrl = (id: string) => photos.get(id) ?? MEDIA[id.split("#")[0]];

// ── The Settings window ─────────────────────────────────────────────────────
// The app's own Settings page, opened by the gear. On the download page it is
// laid over the page (the page owns that); opened on its own, over the island.
const IN_SETTINGS = location.pathname.endsWith("settings.html");
let settingsFrame: HTMLIFrameElement | null = null;
function openSettings(section?: string) {
  if (window.parent !== window) {
    window.parent.postMessage({ type: "notchy-open-settings", section }, "*");
    return;
  }
  if (settingsFrame) return;
  settingsFrame = document.createElement("iframe");
  const url = new URL("./settings.html", location.href);
  url.search = location.search;
  if (section) url.searchParams.set("section", section);
  settingsFrame.src = url.href;
  settingsFrame.title = "Settings";
  Object.assign(settingsFrame.style, {
    position: "fixed", top: "60px", left: "50%", width: "720px", height: "560px",
    transform: "translateX(-50%)", border: "0", zIndex: "60", borderRadius: "12px",
    boxShadow: "0 30px 80px rgba(0,0,0,.6)", colorScheme: "dark",
  });
  document.body.append(settingsFrame);
}
if (!IN_SETTINGS && window.parent === window) {
  window.addEventListener("message", (e) => {
    if (e.data?.type === "notchy-close-settings") { settingsFrame?.remove(); settingsFrame = null; }
    if (e.data?.type === "notchy-settings-saved") emitLocal("settings-changed", e.data.settings);
  });
}

export async function invoke<T>(cmd: string, args: Record<string, any> = {}): Promise<T> {
  switch (cmd) {
    case "boot": {
      const boot: BootInfo = {
        settings: { ...(demoSettings() as BootInfo["settings"]) },
        screen: { x: 0, y: 0, width: 760, height: 700, scale: 2, workX: 0, workY: 0, workWidth: 760, workHeight: 700 },
        version: "0.1.29",
        cursorPoll: false,
        media: true,
        recovered: false,
        accountName: "Cauã Toledo",
        // Only the hero says hello; a feature box opens straight on its card.
        welcome: IN_SETTINGS || SCENE === "hero" || SCENE === "greet" ? null : "skip",
      };
      return boot as T;
    }
    case "secret_present":
      return true as T;
    case "clipboard_entries":
      return [IN_CLIPBOARD ? clipEntries : clipboard(), false] as T;
    case "clipboard_copy": {
      const entry = clipEntries.find((c) => c.id === args.id);
      try { if (entry) await navigator.clipboard?.writeText(entry.body); } catch {}
      return true as T;
    }
    case "clipboard_toggle_favourite":
      clipEntries = clipEntries.map((c) => (c.id === args.id ? { ...c, favourite: !c.favourite } : c));
      return null as T;
    case "clipboard_remove":
      clipEntries = clipEntries.filter((c) => c.id !== args.id);
      return null as T;
    case "clipboard_clear":
      clipEntries = clipEntries.filter((c) => c.favourite);
      return null as T;
    case "toggle_clipboard_window":
      toggleClip();
      return null as T;
    case "close_clipboard_window":
      if (IN_CLIPBOARD) window.parent?.postMessage({ type: "notchy-clip-close" }, "*");
      else closeClip();
      return null as T;
    case "volume_get":
      return volume as T;
    case "volume_set":
      volume = { ...volume, level: Number(args.level ?? volume.level) };
      return null as T;
    case "volume_set_muted":
      volume = { ...volume, muted: !!args.muted };
      return null as T;
    case "media_command": {
      if (!mediaState) return null as T;
      const a = args.action as string;
      if (a === "play") mediaState = { ...mediaState, isPlaying: true };
      else if (a === "pause") mediaState = { ...mediaState, isPlaying: false };
      else if (a === "playpause") mediaState = { ...mediaState, isPlaying: !mediaState.isPlaying };
      else if (a === "next" || a === "previous") mediaState = { ...mediaState, elapsed: 0 };
      else if (a === "seek") mediaState = { ...mediaState, elapsed: Math.max(0, Math.min(mediaState.duration, Number(args.position ?? 0))) };
      emitLocal("media", mediaState);
      return null as T;
    }
    case "media_open_source":
      outside("Music");
      return null as T;
    case "mattermost_photo": {
      const url = mediaUrl(String(args.fileId));
      if (!url) throw new Error("no photo");
      return (await (await fetch(url)).arrayBuffer()) as T;
    }
    case "ato_voice_note": {
      const url = mediaUrl(String(args.storageFileId));
      if (!url) throw new Error("no voice note");
      return (await (await fetch(url)).arrayBuffer()) as T;
    }
    case "save_settings": {
      const next = args.settings;
      try { sessionStorage.setItem(SAVED_KEY, JSON.stringify(next)); } catch {}
      window.parent?.postMessage({ type: "notchy-settings-saved", settings: next }, "*");
      return null as T;
    }
    case "mattermost_sign_in":
    case "ato_sign_in":
    case "whatsapp_show_login":
    case "whatsapp_sign_out":
    case "show_onboarding":
    case "update_check":
    case "update_install":
      outside(cmd);
      return null as T;
    case "mattermost_send_reply":
    case "ato_send_reply":
    case "whatsapp_send_reply":
      await sleep(450);
      outside(cmd.startsWith("mattermost") ? "Mattermost" : cmd.startsWith("ato") ? "Ato" : "WhatsApp Web");
      return null as T;
    case "chat_send":
      await sleep(1100);
      return { text: S.chat } as T;
    case "agenda_refresh":
      return { status: "ready", detail: null, fetchedAtMs: Date.now(), meetings: meetings() } as T;
    case "open_url":
      outside(String(args.url ?? "a link"));
      return null as T;
    case "page_show":
      return pageShow(args.label, Number(args.x), Number(args.y), Number(args.width), Number(args.height)) as T;
    case "page_hide":
      pageHide(args.label);
      return null as T;
    case "page_hide_all":
      pageHide();
      return null as T;
    case "page_open_in_browser":
      pageOpenInBrowser(args.label);
      return null as T;
    case "open_settings_window":
      openSettings(typeof args.section === "string" ? args.section : undefined);
      return null as T;
    case "open_message_service":
    case "open_application":
    case "agenda_open":
    case "mattermost_open_photo":
      outside(cmd);
      return null as T;
    default:
      return null as T;
  }
}

export function transformCallback() { return 0; }
export function convertFileSrc(path: string) { return path; }
export class Channel<T> { onmessage: (m: T) => void = () => {}; }
