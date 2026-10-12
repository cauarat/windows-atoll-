// The TypeScript attachment rules, checked against the Swift ones.
//
// ReplyAttachment.swift and core/attachments.ts are a hand-kept pair. A limit,
// a kind or a MIME type gained on one side and missed on the other means one
// platform silently refuses a file the other accepts — the sort of thing that
// is only ever reported as "it works on my Mac". The Swift suite dumps its
// catalogue and this compares, so drift is a failing build.
//
// Run by scripts/test-reply-attachments.sh, which supplies CATALOG.

import { readFileSync } from "node:fs";
import {
  AttachmentLimits, KNOWN_EXTENSIONS, acceptAttachments, kindFor, mimeTypeFor,
  rejectionMessage, sizeLabel, baseName, extensionOf,
  type AttachmentKind,
} from "../windows/src/core/attachments.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

const rows = readFileSync(process.env.CATALOG!, "utf8")
  .trim().split("\n").map((line) => line.split("\t"));

// ── The same kinds, claiming the same extensions ─────────────────────────────

console.log("\nThe catalogue matches Swift");

for (const [tag, key, value] of rows.filter((r) => r[0] === "kind")) {
  const mine = KNOWN_EXTENSIONS
    .filter((ext) => kindFor(ext) === (key as AttachmentKind))
    .sort()
    .join(",");
  check(mine === value, `${key} — ${value || "(none)"}`);
  void tag;
}

// ── The same ceilings ────────────────────────────────────────────────────────

console.log("\nThe limits match Swift");

const limits: Record<string, number> = {
  maxCount: AttachmentLimits.maxCount,
  maxBytesPerFile: AttachmentLimits.maxBytesPerFile,
  maxTotalBytes: AttachmentLimits.maxTotalBytes,
};
for (const [, key, value] of rows.filter((r) => r[0] === "limit")) {
  check(limits[key] === Number(value), `${key} = ${value}`);
}

// ── The same answer about who can carry a file ───────────────────────────────

console.log("\nSources match Swift");

// Mirrors MessageSource.supportsAttachments. Kept here rather than imported
// because the TS side spells the capability inline where it is used.
const SUPPORTS_ATTACHMENTS: Record<string, boolean> = {
  mattermost: true,
  clickmassa: false,
};
for (const [, key, value] of rows.filter((r) => r[0] === "source")) {
  check(SUPPORTS_ATTACHMENTS[key] === (value === "true"),
        `${key} ${value === "true" ? "can" : "cannot"} take files`);
}

// ── The rules behave the same ────────────────────────────────────────────────

console.log("\nIntake behaves the same");

const file = (name: string, byteCount = 1024) => ({ path: `/tmp/${name}`, byteCount });

const two = acceptAttachments([file("spec.pdf"), file("shot.png")], []);
check(two.accepted.map((a) => a.name).join(",") === "spec.pdf,shot.png", "both land");
check(two.rejected.length === 0, "nothing is refused");

const dupe = acceptAttachments([file("spec.pdf")], two.accepted);
check(dupe.accepted.length === 0 && rejectionMessage(dupe.rejected[0]!) === "spec.pdf is already attached.",
      "the same file twice");

const sameGesture = acceptAttachments([file("a.png"), file("a.png")], []);
check(sameGesture.accepted.length === 1, "the same file twice in one drop");

const big = acceptAttachments([file("huge.mov", 21 * 1024 * 1024)], []);
check(rejectionMessage(big.rejected[0]!) === "huge.mov is over 20 MB.", "over the per-file ceiling");

const folder = acceptAttachments([{ path: "/tmp/Docs", byteCount: 0, isRegularFile: false }], []);
check(rejectionMessage(folder.rejected[0]!) === "Docs is a folder.", "a folder");

const many = acceptAttachments(Array.from({ length: 12 }, (_, i) => file(`f${i + 1}.txt`)), []);
check(many.accepted.length === 10, "ten at most");
check(many.rejected.length === 1 && rejectionMessage(many.rejected[0]!) === "That is more than 10 files.",
      "and says so once, not twice");

const heavy = acceptAttachments(
  Array.from({ length: 4 }, (_, i) => file(`v${i + 1}.mov`, 15 * 1024 * 1024)), []);
check(heavy.accepted.length === 3, "the total ceiling holds");
check(rejectionMessage(heavy.rejected[0]!) === "v4.mov would take the reply over 50 MB.",
      "…and names the one that broke it");

const mixed = acceptAttachments([file("huge.mov", 99 * 1024 * 1024), file("fine.txt")], []);
check(mixed.accepted.map((a) => a.name).join(",") === "fine.txt",
      "a refusal never costs an acceptance");

// ── Sizes and types read the same ────────────────────────────────────────────

console.log("\nSizes and types match Swift");

check(sizeLabel(512) === "512 B", "bytes stay bytes");
check(sizeLabel(2048) === "2.0 KB", "a kilobyte");
check(sizeLabel(15 * 1024 * 1024) === "15 MB", "a big one loses the decimal");

check(kindFor("HEIC") === "image", "case does not matter");
check(kindFor("xyz") === "other", "an unknown extension");
check(mimeTypeFor("PNG") === "image/png", "png");
check(mimeTypeFor("pdf") === "application/pdf", "pdf");
check(mimeTypeFor("xyz") === "application/octet-stream", "something unknown");

// Windows paths are the ones Rust will hand over on that platform.
check(baseName("C:\\Users\\x\\a.png") === "a.png", "a Windows path");
check(baseName("/tmp/a.png") === "a.png", "a Unix path");
check(extensionOf("/tmp/archive.tar.gz") === "gz", "the last extension wins");
check(extensionOf("/tmp/.gitignore") === "", "a dotfile has none");

console.log("");
if (failures === 0) {
  console.log("All reply attachment parity checks passed.");
} else {
  console.log(`${failures} failure(s).`);
  process.exit(1);
}
