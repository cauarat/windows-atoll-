import { defineConfig, type Plugin } from "vite";
import { existsSync, mkdirSync, readdirSync, copyFileSync, createReadStream } from "node:fs";
import { resolve, join, extname } from "node:path";

// ───────────────────────────────────────────────────────────────────────────────
// THE one and only place the shared sound folder is declared.
// The 28 WAVs live in the macOS app and are NOT duplicated in the repo; when they
// move to `shared/sounds/`, change this single line.
export const SOUNDS_DIR = resolve(__dirname, "../NotchBuddy/Resources/sounds");
// ───────────────────────────────────────────────────────────────────────────────

/** The Mac reference captures `scripts/capture-mac-reference.sh` writes. */
const MAC_CAPTURES_DIR = resolve(__dirname, "../design/captures/parity");

/**
 * Serves SOUNDS_DIR at /sounds/*.wav in dev, and copies it into dist/sounds on build.
 * Keeps the WAVs out of windows/ while still shipping them inside the installer.
 */
function sharedSounds(): Plugin {
  const prefix = "/sounds/";
  return {
    name: "coucou-shared-sounds",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (!req.url?.startsWith(prefix)) return next();
        const name = decodeURIComponent(req.url.slice(prefix.length).split("?")[0]);
        if (name.includes("/") || name.includes("\\") || extname(name) !== ".wav") return next();
        const file = join(SOUNDS_DIR, name);
        if (!existsSync(file)) return next();
        res.setHeader("Content-Type", "audio/wav");
        createReadStream(file).pipe(res);
      });
    },
    closeBundle() {
      const out = resolve(__dirname, "dist/sounds");
      if (!existsSync(SOUNDS_DIR)) {
        this.warn(`sounds not found at ${SOUNDS_DIR} — the build will ship without audio`);
        return;
      }
      mkdirSync(out, { recursive: true });
      for (const f of readdirSync(SOUNDS_DIR)) {
        if (extname(f) === ".wav") copyFileSync(join(SOUNDS_DIR, f), join(out, f));
      }
    },
  };
}

/**
 * Dev only: serves the Mac reference captures at /mac-captures/<dir>/<file>.png,
 * and their list at /mac-captures/index.json, for `dev/compare.html`. Nothing
 * of it reaches a build.
 */
function macCaptures(): Plugin {
  const prefix = "/mac-captures/";
  function list(dir: string, base = ""): string[] {
    if (!existsSync(dir)) return [];
    return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
      e.isDirectory() ? list(join(dir, e.name), `${base}${e.name}/`)
        : extname(e.name) === ".png" ? [`${base}${e.name}`] : []);
  }
  return {
    name: "coucou-mac-captures",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (!req.url?.startsWith(prefix)) return next();
        const name = decodeURIComponent(req.url.slice(prefix.length).split("?")[0]);
        if (name === "index.json") {
          res.setHeader("Content-Type", "application/json");
          res.end(JSON.stringify(list(MAC_CAPTURES_DIR).sort()));
          return;
        }
        if (name.split("/").some((part) => part === ".." || part === "") || extname(name) !== ".png") return next();
        const file = join(MAC_CAPTURES_DIR, name);
        if (!existsSync(file)) return next();
        res.setHeader("Content-Type", "image/png");
        createReadStream(file).pipe(res);
      });
    },
  };
}

export default defineConfig({
  plugins: [sharedSounds(), macCaptures()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: "127.0.0.1",
    // A desktop `tauri dev` build gets its pages straight from here, and the
    // CSP in tauri.conf.json is only ever sent by Tauri's own protocol: who
    // may frame them is said here too. Checked by web.rs's
    // no_page_of_coucous_can_be_framed.
    headers: { "Content-Security-Policy": "frame-ancestors 'self'" },
  },
  envPrefix: ["VITE_", "TAURI_ENV_"],
  build: {
    target: "chrome110",
    minify: "esbuild",
    sourcemap: false,
    emptyOutDir: true,
    rollupOptions: {
      input: {
        island: resolve(__dirname, "index.html"),
        settings: resolve(__dirname, "settings.html"),
        clipboard: resolve(__dirname, "clipboard.html"),
        onboarding: resolve(__dirname, "onboarding.html"),
      },
    },
  },
});
