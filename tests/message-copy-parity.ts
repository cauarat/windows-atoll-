// What Copy copies, on Windows, checked against the Mac.
//
// `MessageCopy.content` and `core/messageCopy.ts`'s `copyKind` and
// `copyFiles` are a hand-kept pair. A pair that drifts is a card that offers
// Copy on one platform and not the other, copies "📎 Sent a file" where the
// other copies the PDF, or one photo of an album where the other copies all.
//
// Run by scripts/test-message-copy.sh, which supplies TABLE.

import { readFileSync } from "node:fs";
import { copyFiles, copyKind, type CopyFile } from "../windows/src/core/messageCopy.ts";

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`  ${ok ? "✓" : "✗"} ${what}`);
  if (!ok) failures++;
};

// The same files MessageCopyTests.swift builds its rows from.
const photoFile: CopyFile = { fileId: "abc", name: "IMG_1.jpg", mimeType: "image/jpeg", byteCount: 1000 };
const audioFile: CopyFile = { fileId: "s1", name: "audio.ogg", mimeType: "audio/ogg", byteCount: 5120 };
const others: CopyFile[] = [
  { fileId: "f1", name: "boleto.pdf", mimeType: "application/pdf", byteCount: 80213 },
  { fileId: "f2", name: "notas.xlsx", mimeType: "application/vnd.ms-excel", byteCount: 9000 },
];

const rows = readFileSync(process.env.TABLE!, "utf8").trim().split("\n").map((line) => line.split("\t"));

console.log("\nA card copies here what Swift says it copies");

for (const [encoded, hasPhoto, hasAudio, extra, expectedKind, expectedCount] of rows) {
  const text = encoded === "<nil>" ? null : encoded.replace(/\\n/g, "\n");
  const photo = hasPhoto === "true";
  const audio = hasAudio === "true";
  const message = {
    text,
    photo: photo ? photoFile : null,
    audio: audio ? { storageFileId: "s1" } : null,
    files: [...(photo ? [photoFile] : []), ...(audio ? [audioFile] : []), ...others.slice(0, Number(extra))],
  };
  const kind = copyKind(message) ?? "none";
  // A voice message is copied as its own audio file, not through copyFiles.
  const count = kind === "voice" ? 1 : copyFiles(message).length;
  const ok = kind === expectedKind && String(count) === expectedCount;
  check(ok,
        `text ${JSON.stringify(text)}, photo ${hasPhoto}, audio ${hasAudio}, ${extra} more → `
        + `${expectedKind}, ${expectedCount} file(s)` + (ok ? "" : ` (got ${kind}, ${count})`));
}

console.log("\nAn album is copied photo first, the rest in the order they were sent");
const album = copyFiles({ photo: photoFile, files: [others[0], photoFile, others[1]] });
check(album.map((file) => file.fileId).join(",") === "abc,f1,f2", album.map((file) => file.fileId).join(","));

console.log("");
if (failures === 0) console.log("All good.");
else { console.log(`${failures} failed.`); process.exit(1); }
