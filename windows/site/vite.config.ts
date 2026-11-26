// Builds the island for the download page: the app's own code, with Tauri
// swapped for site/shim, the MacBook's notch geometry, and the sounds beside it.
//
//   npx vite build --config site/vite.config.ts            # once
//   npx vite build --config site/vite.config.ts --watch    # while editing
//
// Output: docs/live/island/, which the page loads in an <iframe> per island.

import { defineConfig, type Plugin } from "vite";
import { resolve, extname, join } from "node:path";
import { existsSync, mkdirSync, readdirSync, copyFileSync } from "node:fs";

const SITE = __dirname;
const OUT = resolve(SITE, "../../docs/live/island");
const SOUNDS = resolve(SITE, "../../NotchBuddy/Resources/sounds");
/** phone.bubble.fill in the ring's 24-point box: settings/icons.ts's path, scaled. */
const WA = "M5.25 2.91H18.56A3 3 0 0 1 21.56 5.91V14.72A3 3 0 0 1 18.56 17.72H11.62L8.36 20.98C7.95 21.39 7.2 21.36 6.9 21.02C6.79 20.89 6.75 20.72 6.75 20.53V17.72H5.25A3 3 0 0 1 2.25 14.72V5.91A3 3 0 0 1 5.25 2.91ZM8.62 5.64C9.09 5.57 9.52 5.83 9.82 6.28L10.43 7.22C10.71 7.67 10.67 8.16 10.35 8.57L9.9 9.32C10.05 10.12 11.06 11.38 12.49 12.17L13.05 11.83C13.61 11.49 14.51 11.49 15.08 11.83L15.86 12.39C16.46 12.84 16.54 13.67 16.01 14.23L15.49 14.68C15 15.09 14.1 15.09 13.24 14.76C11.21 14.04 8.7 11.83 7.61 9.58C7.2 8.72 7.2 7.48 7.5 6.81L7.76 6.32C7.99 5.91 8.29 5.7 8.62 5.64Z";

/**
 * The few places the island has to differ on a web page, done at build time so
 * nothing in src/ carries a website's concerns:
 * - the notch: a PC has none, so its resting island is the bare 184 + 104. On
 *   a MacBook it hangs from a real cutout — 185 × 42 on the Mac this page was
 *   modelled on, with the island 160 wider (IslandWindowController: nw + 160);
 * - sounds load beside the page, not from the site's root;
 * - the island is reachable by the demo, which drives it as Rust would.
 */
function forTheSite(): Plugin {
  return {
    name: "notchy-site",
    enforce: "pre",
    transform(code, id) {
      if (id.endsWith("/src/core/layout.ts")) {
        return code
          .replace(/export const NOTCH_W = \d+;/, "export const NOTCH_W = 185;")
          .replace(/export const NOTCH_H = \d+;/, "export const NOTCH_H = 42;")
          .replace(/export const COMPACT_W = \d+;[^\n]*/, "export const COMPACT_W = 345;");
      }
      if (id.endsWith("/src/core/sound.ts")) {
        return code.replace("fetch(`/sounds/", "fetch(`./sounds/");
      }
      if (id.endsWith("/src/main.ts")) {
        return code.replace(
          "const island = new Island(root);",
          "const island = new Island(root); (window as any).__notchyIsland = island;",
        );
      }
      if (id.endsWith("/src/views/views.ts")) {
        // The apps grid and the site are Windows extras (docs/parity/README.md);
        // the Mac's header holds home, chat and the clipboard.
        return code.replace(
          'h("div", { class: "tabs" }, tabHome, tabChat, tabClip, tabPills, tabSite)',
          'h("div", { class: "tabs" }, tabHome, tabChat, tabClip)',
        );
      }
      if (id.endsWith("/src/island/island.ts")) {
        // WhatsApp on the Mac's ring is phone.bubble.fill (settings/icons.ts),
        // not the ellipsis the Windows ring falls back to.
        // At rest the app shrinks its window to the bar and draws the island at
        // 0,0 in it, with Rust placing that window under the notch. A frame
        // on a page never moves, so here the island always lays itself out in
        // the whole panel, centred, as it does while open.
        return code.replaceAll('this.windowIsBar = this.fold() === "bar";', "this.windowIsBar = false;").replace(
          ": svg(RING_MARKS[button.action] ?? ICONS.ellipsis, 15);",
          `: button.action === "integration_whatsapp"
          ? (() => { const e = svg("${WA}", 15); e.querySelector("path")!.setAttribute("fill-rule", "evenodd"); return e; })()
          : svg(RING_MARKS[button.action] ?? ICONS.ellipsis, 15);`,
        );
      }
      return null;
    },
    closeBundle() {
      if (!existsSync(SOUNDS)) return;
      const dir = join(OUT, "sounds");
      mkdirSync(dir, { recursive: true });
      for (const f of readdirSync(SOUNDS)) if (extname(f) === ".wav") copyFileSync(join(SOUNDS, f), join(dir, f));
    },
  };
}

export default defineConfig({
  root: SITE,
  base: "./",
  publicDir: false,
  resolve: {
    alias: {
      "@tauri-apps/api/core": resolve(SITE, "shim/core.ts"),
      "@tauri-apps/api/event": resolve(SITE, "shim/event.ts"),
      "@tauri-apps/api/webview": resolve(SITE, "shim/webview.ts"),
      "@tauri-apps/plugin-dialog": resolve(SITE, "shim/dialog.ts"),
    },
  },
  plugins: [forTheSite()],
  build: {
    outDir: OUT,
    emptyOutDir: true,
    assetsDir: "assets",
    target: "es2020",
    sourcemap: false,
    rollupOptions: {
      input: {
        index: resolve(SITE, "index.html"),
        clipboard: resolve(SITE, "clipboard.html"),
        settings: resolve(SITE, "settings.html"),
      },
    },
  },
});
