// Writes release/latest.json — the file tauri-plugin-updater fetches to decide
// whether a newer version exists.
//
//   node scripts/update-manifest.mjs <platform-key> <asset> <tag>
//
//   node scripts/update-manifest.mjs windows-x86_64 Notchy-Windows-0.1.4-setup.exe windows-v0.1.4
//   node scripts/update-manifest.mjs linux-x86_64 Notchy-Linux-0.1.4-x86_64.AppImage linux-v0.1.4
//
// Shared by both release workflows so the two manifests cannot drift into
// different shapes, which is the kind of thing that only shows up as an update
// that silently never arrives.
//
// The manifest is published to the rolling `<os>-latest` release, because that
// is the one URL that never changes; the package it points at lives in the
// versioned release, so a half-finished upload to the rolling tag can never
// serve an installer that does not match the signature beside it.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "release");

const [platformKey, asset, tag] = process.argv.slice(2);
if (!platformKey || !asset || !tag) {
  console.error("Usage: node scripts/update-manifest.mjs <platform-key> <asset> <tag>");
  process.exit(1);
}

const repo = process.env.GITHUB_REPOSITORY;
if (!repo) {
  console.error("GITHUB_REPOSITORY is not set — the manifest needs it to build the download URL.");
  process.exit(1);
}

const { version } = JSON.parse(readFileSync(join(root, "src-tauri", "tauri.conf.json"), "utf8"));

// The signature Tauri produced beside the package. Its absence means the build
// ran without createUpdaterArtifacts or without a signing key, and publishing a
// manifest without one would hand every installed copy an update it must then
// refuse.
let signature;
try {
  signature = readFileSync(join(outDir, `${asset}.sig`), "utf8").trim();
} catch {
  console.error(`No ${asset}.sig in ${outDir}. The build did not sign this package.`);
  process.exit(1);
}

/**
 * The "## <version>" section of CHANGELOG.md, flattened to plain lines.
 *
 * Capped, because this file is fetched on every check by every installed copy,
 * and because the settings window shows it in a small box rather than a page.
 */
function notes() {
  const fallback = `Notchy ${version}. See the release page for what changed.`;
  let changelog;
  try {
    changelog = readFileSync(join(root, "..", "CHANGELOG.md"), "utf8");
  } catch {
    return fallback;
  }
  const lines = changelog.split("\n");
  const start = lines.findIndex(
    (line) => line === `## ${version}` || line.startsWith(`## ${version} `),
  );
  if (start === -1) return fallback;

  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith("## ")) break;
    body.push(line);
  }
  const text = body.join("\n").trim();
  if (!text) return fallback;
  return text.length > 1200 ? `${text.slice(0, 1200).trimEnd()}…` : text;
}

const manifest = {
  version,
  notes: notes(),
  // Seconds only: milliseconds are valid RFC 3339 but there is no reason to
  // publish them.
  pub_date: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
  platforms: {
    [platformKey]: {
      signature,
      url: `https://github.com/${repo}/releases/download/${tag}/${asset}`,
    },
  },
};

const dest = join(outDir, "latest.json");
writeFileSync(dest, `${JSON.stringify(manifest, null, 2)}\n`);

// The signature itself is long and says nothing to a human reading the log.
console.log(`\n  ${dest}`);
console.log(`  version   ${manifest.version}`);
console.log(`  platform  ${platformKey}`);
console.log(`  url       ${manifest.platforms[platformKey].url}`);
console.log(`  signed    ${signature.length} characters\n`);
