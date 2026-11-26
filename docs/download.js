// The download page: its language, which system this is, the newest build of
// each, the first-launch guide, the sheet that follows a download, and the live
// islands — Notchy's own island (windows/site builds it into live/island/), one
// frame per place, with the app's Settings behind the gear.
//
// The version, date, size and links come from the GitHub releases API at load
// time, as before: publishing a release updates the page with no edit here.
// Until that answers, every button points at the releases page, which is always
// a real destination; a platform with nothing published says so.

import { I18N } from "./download-i18n.js";

// ── Language ─────────────────────────────────────────────────────────────────
// `?lang=` (the switch in the nav), then `#es`/`#pt` (the old page's anchors),
// then the last one picked here, then the browser's. English otherwise.
const LANGS = ["en", "es", "pt"];
const asked = new URLSearchParams(location.search).get("lang") ?? location.hash.slice(1);
let stored = null;
try { stored = localStorage.getItem("notchy-site-lang"); } catch {}
const browser = (navigator.language || "en").slice(0, 2).toLowerCase();
const LANG = [asked, stored, browser].find((l) => LANGS.includes(l)) ?? "en";
try { if (LANGS.includes(asked)) localStorage.setItem("notchy-site-lang", asked); } catch {}
/** The island's own language code: the app says pt-BR. */
const ISLAND_LANG = LANG === "pt" ? "pt-BR" : LANG;
const LOCALE = LANG === "pt" ? "pt-BR" : LANG;
const DICT = I18N[LANG] ?? {};
/** Megabytes, one decimal, in the page's own notation (12,7 in pt and es). */
const mb1 = (bytes) => (bytes / 1048576).toLocaleString(LOCALE, { minimumFractionDigits: 1, maximumFractionDigits: 1 });

/** A sentence in the page's language; `%s` takes the arguments in turn. */
function t(key, ...args) {
  let out = DICT[key] ?? key;
  for (const a of args) out = out.replace("%s", a);
  return out;
}

/** Translates the words and labels under `root` in place. */
function translate(root) {
  if (LANG === "en" || !root) return;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) => (n.parentElement?.closest("script, style, code, svg") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
  });
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const raw = n.nodeValue;
    const key = raw.replace(/\s+/g, " ").trim();
    if (!key || !(key in DICT)) continue;
    const lead = /^\s/.test(raw) ? " " : "";
    const trail = /\s$/.test(raw) ? " " : "";
    n.nodeValue = lead + DICT[key] + trail;
  }
  for (const el of root.querySelectorAll("[title], [aria-label], [alt], [placeholder]")) {
    for (const attr of ["title", "aria-label", "alt", "placeholder"]) {
      const v = el.getAttribute(attr);
      if (v && v in DICT) el.setAttribute(attr, DICT[v]);
    }
  }
}

document.documentElement.lang = LOCALE;
document.title = t("Download Notchy");
translate(document.body);
document.querySelectorAll(".lang [data-lang]").forEach((a) => {
  if (a.dataset.lang === LANG) a.setAttribute("aria-current", "true");
  else a.removeAttribute("aria-current");
});
// Every island speaks the page's language. Loaded only now, so none starts in
// the wrong one; the sheet's waits for a download.
document.querySelectorAll("iframe[data-src]").forEach((f) => {
  f.dataset.src = f.dataset.src.replace("{lang}", ISLAND_LANG);
  if (!f.classList.contains("js-later")) f.src = f.dataset.src;
});

const REPO = "cauarat/windows-atoll-";
const RELEASES = `https://github.com/${REPO}/releases`;

const ua = navigator.userAgent || "";
const OS = /Windows/i.test(ua) ? "win" : /Linux|X11|CrOS/i.test(ua) && !/Android/i.test(ua) ? "linux" : "mac";

const ICON = {
  mac: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5V16H4z"/><path d="M10 4v1a1 1 0 0 0 1 1h2a1 1 0 0 0 1-1V4"/><path d="M2 19.5h20"/></svg>`,
  win: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3.5" y="3.5" width="7.5" height="7.5" rx="1"/><rect x="13" y="3.5" width="7.5" height="7.5" rx="1"/><rect x="3.5" y="13" width="7.5" height="7.5" rx="1"/><rect x="13" y="13" width="7.5" height="7.5" rx="1"/></svg>`,
  linux: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M7 9l3 3-3 3"/><path d="M12.5 15H17"/></svg>`,
};

const PLATFORM = {
  mac: {
    label: "Download for Mac", others: "Windows and Linux", match: /\.dmg$/i,
    meta: "macOS 15 or later · Intel and Apple silicon",
    s1t: "Drag it to Applications", s1b: "Open the .dmg and drag Notchy onto the Applications folder.",
    s2t: "Open Anyway, once", s2b: "Notchy has no Apple Developer ID yet, so macOS asks first. System Settings → Privacy & Security → Open Anyway.",
    s3b: "Mochi waves from the notch, then a short welcome sets your name, look and tools. Hover the island above — it’s live.",
    pic1: `<div class="mini-window"><div class="drag-row"><figure><img src="media/icon.png" alt="" width="60" height="60">Notchy</figure>
      <svg width="40" height="20" viewBox="0 0 40 20" fill="none" stroke="#9ca3af" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 10h34M28 3l8 7-8 7"/></svg>
      <figure><svg width="60" height="60" viewBox="0 0 64 64" aria-hidden="true"><path d="M6 18a5 5 0 0 1 5-5h14l5 6h23a5 5 0 0 1 5 5v24a5 5 0 0 1-5 5H11a5 5 0 0 1-5-5z" fill="#5aa9f5"/><path d="M6 24h52v24a5 5 0 0 1-5 5H11a5 5 0 0 1-5-5z" fill="#79bbf8"/><path d="M26 30l6 8 6-8" stroke="#fff" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>Applications</figure></div></div>`,
    pic2: `<div class="mini-window"><b>Privacy &amp; Security</b><p style="margin:10px 0 0;color:#374151">“Notchy” was blocked to protect your Mac.</p><div class="ok"><span>Open Anyway</span></div></div>`,
  },
  win: {
    label: "Download for Windows", others: "Mac and Linux", match: /-setup\.exe$/i,
    meta: "Windows 10 and 11 · 64-bit",
    s1t: "Run the installer", s1b: "It adds Notchy to the Start menu. Remove it any time from Settings → Apps.",
    s2t: "More info → Run anyway", s2b: "SmartScreen warns because the build is new and unsigned, not because anything was found in it. Blocked outright? Use the portable .zip.",
    s3b: "Mochi appears in the corner you pick, and the welcome walks you through the rest.",
    pic1: `<div class="mini-window" style="display:flex;align-items:center;gap:14px"><img src="media/icon.png" alt="" width="46" height="46"><div style="min-width:0"><b class="js-sheet-file2" style="font-family:var(--mono);font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">Notchy setup</b><span style="color:#6b7280">Open file</span></div></div>`,
    pic2: `<div class="mini-smart"><b>Windows protected your PC</b><u>More info</u><div class="ok"><span>Run anyway</span></div></div>`,
  },
  linux: {
    label: "Download for Linux", others: "Mac and Windows", match: /\.AppImage$/i,
    meta: "AppImage, .deb or .rpm · x86_64 · Beta",
    s1t: "Make it runnable", s1b: "Mark the AppImage executable and open it. The .deb and .rpm install like any package.",
    s2t: "Where it sits", s2b: "Over your panel on KDE Plasma, COSMIC, Hyprland and Sway; on GNOME, as a regular window.",
    s3b: "Mochi says hi from the top of the screen. Keys you connect go to the Secret Service.",
    pic1: `<div class="mini-term"><s>$</s> chmod +x Notchy-*.AppImage<br><s>$</s> ./Notchy-*.AppImage</div>`,
    pic2: `<div class="mini-window"><b>KDE Plasma · COSMIC · Hyprland · Sway</b><span style="color:#6b7280">over your panel</span><b style="margin-top:10px">GNOME</b><span style="color:#6b7280">a regular window</span></div>`,
  },
};

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

// ── This system ──────────────────────────────────────────────────────────────
// A guess, so it only adds a hint: the other cards stay, because people often
// download for a machine they are not sitting at.
const here = PLATFORM[OS];
$$(".js-cta-label").forEach((el) => (el.textContent = t(here.label)));
$$(".js-os-icon").forEach((el) => (el.innerHTML = ICON[OS]));
$$(".js-cta-others").forEach((el) => (el.textContent = t(here.others)));
$(".js-cta-meta").textContent = t(here.meta);
$$(".dl-card").forEach((card) => {
  if (card.dataset.platform !== OS) return;
  card.classList.add("likely");
  $(".js-yours", card).hidden = false;
});

// ── Newest build of each ─────────────────────────────────────────────────────
const found = {};
const fmtDate = (iso) => {
  try { return new Date(iso).toLocaleDateString(LOCALE, { year: "numeric", month: "short", day: "numeric" }); } catch { return ""; }
};

fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, { headers: { Accept: "application/vnd.github+json" } })
  .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
  .then((releases) => {
    let newest = null;
    $$(".dl-card").forEach((card) => {
      const key = card.dataset.platform;
      const p = PLATFORM[key];
      const meta = $(".js-meta", card);
      let hit = null;
      // Newest first, and never a draft: a half-published release must not
      // become the download this page offers.
      for (const rel of releases) {
        if (rel.draft) continue;
        const asset = (rel.assets || []).find((a) => p.match.test(a.name));
        if (asset) { hit = { rel, asset }; break; }
      }
      if (!hit) { meta.textContent = t("No release published for this platform yet."); return; }
      found[key] = hit;
      const btn = $(".js-btn", card);
      btn.href = hit.asset.browser_download_url;
      btn.dataset.direct = key;
      $$(".js-alt", card).forEach((a) => {
        const alt = (hit.rel.assets || []).find((x) => new RegExp(a.dataset.match, "i").test(x.name));
        if (alt) { a.href = alt.browser_download_url; a.dataset.direct = key; a.dataset.file = alt.name; a.dataset.size = alt.size; }
      });
      const version = (hit.rel.tag_name || "").replace(/^[a-z]+-v?/i, "");
      const mb = hit.asset.size ? `${mb1(hit.asset.size)} MB · ` : "";
      meta.textContent = `v${version} · ${mb}${fmtDate(hit.rel.published_at)}`;
      if (!newest || hit.rel.published_at > newest.published_at) newest = hit.rel;
    });
    if (newest) $(".js-release-text").textContent = t("Version %s is out", (newest.tag_name || "").replace(/^[a-z]+-v?/i, ""));
    if (newest) $(".js-release-badge").href = newest.html_url;
    if (found[OS]) {
      $$(".js-dl").forEach((a) => { a.href = found[OS].asset.browser_download_url; a.dataset.direct = OS; });
      const mb = mb1(found[OS].asset.size);
      $(".js-cta-meta").textContent = `${t(here.meta)} · ${mb} MB`;
    }
  })
  .catch(() => {
    // Rate-limited or offline. The buttons still go to the releases page.
    $$(".js-meta").forEach((m) => (m.textContent = t("Pick the newest build on the releases page.")));
  });

// ── First-launch guide ───────────────────────────────────────────────────────
function showGuide(key) {
  $$(".seg [data-guide]").forEach((b) => b.setAttribute("aria-selected", String(b.dataset.guide === key)));
  $$(".js-guide").forEach((g) => (g.hidden = g.dataset.guide !== key));
}
$$(".seg [data-guide]").forEach((b) => b.addEventListener("click", () => showGuide(b.dataset.guide)));
showGuide(OS);

$$(".js-copy").forEach((btn) => btn.addEventListener("click", () => {
  const code = btn.parentElement.querySelector("code").textContent;
  navigator.clipboard?.writeText(code).catch(() => {});
  btn.textContent = t("Copied");
  setTimeout(() => (btn.textContent = t("Copy")), 1800);
}));

// ── After a download starts ──────────────────────────────────────────────────
const sheet = $(".js-sheet");
let sheetIslandMounted = false;
function openSheet(key, file, size) {
  const p = PLATFORM[key];
  $(".js-sheet-file").textContent = file;
  $(".js-sheet-size").textContent = size ? ` · ${mb1(size)} MB` : "";
  $(".js-sheet-retry").href = found[key]?.asset.browser_download_url || RELEASES;
  $(".js-sheet-pic1").innerHTML = p.pic1;
  $(".js-sheet-pic2").innerHTML = p.pic2;
  const f2 = $(".js-sheet-file2");
  if (f2) f2.textContent = file;
  translate($(".js-sheet-pic1"));
  translate($(".js-sheet-pic2"));
  $(".js-s1t").textContent = t(p.s1t);
  $(".js-s1b").textContent = t(p.s1b);
  $(".js-s2t").textContent = t(p.s2t);
  $(".js-s2b").textContent = t(p.s2b);
  $(".js-s3b").textContent = t(p.s3b);
  sheet.hidden = false;
  requestAnimationFrame(() => sheet.classList.add("show"));
  if (!sheetIslandMounted) {
    // Loaded only now, so Mochi says hello when there is someone to see it.
    sheetIslandMounted = true;
    const f = $(".js-later", sheet);
    f.src = f.dataset.src;
    fitFrame(f);
  }
  $(".js-sheet-close", sheet).focus();
}
function closeSheet() {
  sheet.classList.remove("show");
  setTimeout(() => (sheet.hidden = true), 200);
}
document.addEventListener("click", (e) => {
  const a = e.target.closest("a[data-direct]");
  if (!a) return;
  const key = a.dataset.direct;
  const hit = found[key];
  // The browser downloads the file as usual; the sheet only explains what next.
  setTimeout(() => openSheet(key, a.dataset.file || hit?.asset.name || "Notchy", Number(a.dataset.size || hit?.asset.size || 0)), 50);
});
$$(".js-sheet-close").forEach((b) => b.addEventListener("click", closeSheet));
sheet.addEventListener("click", (e) => { if (e.target === sheet) closeSheet(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !sheet.hidden) closeSheet(); });

// ── The live islands ─────────────────────────────────────────────────────────
// Each frame is 760 wide inside and zooms itself down to fit; its height
// follows, so nothing below it moves when the page narrows.
const frames = $$(".island-frame");
const fitFrame = (f) => {
  const w = f.clientWidth || 760;
  // Never less than its set height, and taller while the island needs it —
  // ChatGPT's page, the clipboard window (`notchy-height`, below).
  const tall = Math.max(Number(f.dataset.base), Number(f.dataset.need ?? 0));
  f.style.height = `${Math.round(tall * Math.min(1, w / 760))}px`;
};
window.addEventListener("message", (e) => {
  if (e.data?.type !== "notchy-height") return;
  const f = $$(".island-frame").find((x) => x.contentWindow === e.source);
  if (!f) return;
  f.dataset.need = String(e.data.need);
  fitFrame(f);
});
const ro = new ResizeObserver((entries) => entries.forEach((e) => fitFrame(e.target)));
frames.forEach((f) => { fitFrame(f); ro.observe(f); });

// What the island would open outside itself — Mattermost, a link, Settings —
// is a click away in the app, and only a note here.
const toast = $(".js-toast");
let toastTimer;
const OUTSIDE = {
  open_message_service: "the conversation", open_application: "the app", open_in_vscode: "VS Code",
  agenda_open: "the agenda", mattermost_open_photo: "the photo", mattermost_sign_in: "the Mattermost sign-in",
  ato_sign_in: "the Ato sign-in", whatsapp_show_login: "WhatsApp Web", whatsapp_sign_out: "WhatsApp Web",
  show_onboarding: "the welcome", update_check: "the update check", update_install: "the update",
};
window.addEventListener("message", (e) => {
  if (e.data?.type !== "notchy-demo-outside") return;
  const what = OUTSIDE[e.data.what] ?? e.data.what;
  toast.textContent = /^https?:/.test(what) ? t("In the app, this opens the link in your browser") : t("In the app, this opens %s", t(what));
  toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("show"), 2400);
});

// ── Settings ─────────────────────────────────────────────────────────────────
// The island's gear opens Notchy's own Settings window over the page; what is
// saved there — from it or from the Characters pane in the page — reaches every
// island at once, as Rust's "settings-changed" does in the app.
const settingsBack = $(".js-settings");
const settingsFrame = $(".js-settings-frame");
const tellIslands = (msg) => frames.forEach((f) => f.contentWindow?.postMessage(msg, "*"));
function openSettings(section) {
  const url = new URL("live/island/settings.html", location.href);
  url.searchParams.set("lang", ISLAND_LANG);
  if (section) url.searchParams.set("section", section);
  settingsFrame.src = url.href;
  settingsBack.hidden = false;
  requestAnimationFrame(() => settingsBack.classList.add("show"));
}
function closeSettings() {
  settingsBack.classList.remove("show");
  setTimeout(() => { settingsBack.hidden = true; settingsFrame.removeAttribute("src"); }, 200);
}
$(".js-settings-close").addEventListener("click", closeSettings);
settingsBack.addEventListener("click", (e) => { if (e.target === settingsBack) closeSettings(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !settingsBack.hidden) closeSettings(); });
window.addEventListener("message", (e) => {
  if (e.data?.type === "notchy-open-settings") openSettings(e.data.section);
  if (e.data?.type === "notchy-settings-saved") tellIslands({ type: "notchy-settings", settings: e.data.settings });
});

// ── Notifications ────────────────────────────────────────────────────────────
// While the visitor is on the page, a message arrives now and then — never two
// in a row: one comes in, its card folds after a few seconds, and a while later
// the next arrives from another app. It goes to the island the visitor can see.
const listeners = frames.filter((f) => /scene=(hero|rest)/.test(f.getAttribute("src") ?? ""));
const seen = new Map();
const io = new IntersectionObserver((entries) => entries.forEach((e) => seen.set(e.target, e.intersectionRatio)),
  { threshold: [0, 0.25, 0.5, 0.75, 1] });
listeners.forEach((f) => io.observe(f));
const inView = () => listeners
  .filter((f) => (seen.get(f) ?? 0) >= 0.5)
  .sort((a, b) => (seen.get(b) ?? 0) - (seen.get(a) ?? 0))[0];
const quietPage = () => document.hidden || !settingsBack.hidden || !sheet.hidden;
let delivered = 0;
let retryTimer;
function scheduleNotification(ms) {
  clearTimeout(retryTimer);
  retryTimer = setTimeout(() => {
    const target = inView();
    if (!target || quietPage()) return scheduleNotification(5000);
    target.contentWindow?.postMessage({ type: "notchy-deliver" }, "*");
  }, ms);
}
window.addEventListener("message", (e) => {
  if (e.data?.type !== "notchy-delivered") return;
  if (!e.data.shown) return scheduleNotification(6000);
  delivered++;
  // Now and then the agent in the hero gets back to work instead.
  if (delivered % 4 === 0) setTimeout(() => $(".shot-wrap .island-frame")?.contentWindow?.postMessage({ type: "notchy-agent" }, "*"), 12_000);
  scheduleNotification(22_000 + Math.random() * 10_000);
});
// The first one once the hero has said hello and its agent has started.
scheduleNotification(34_000);

// ── The first click ──────────────────────────────────────────────────────────
// Browsers keep a page silent until it is clicked. The islands' sounds — and the
// hero's Christmas music, which Notchy starts with its greeting — wait for it.
const activate = () => tellIslands({ type: "notchy-activate" });
window.addEventListener("pointerdown", activate, { once: true });
window.addEventListener("keydown", activate, { once: true });

// The hero's Christmas music starts with its greeting. Where the browser holds
// its sound back until a click, it plays muted and this button offers the
// click; any other click or key on the page does the same.
const soundBtn = $(".js-sound");
soundBtn.addEventListener("click", () => { activate(); soundBtn.hidden = true; });
window.addEventListener("message", (e) => {
  if (e.data?.type === "notchy-music") soundBtn.hidden = e.data.state !== "muted";
});

