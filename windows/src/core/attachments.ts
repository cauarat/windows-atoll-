/**
 * Files staged on a reply, before it is sent.
 *
 * The hand-kept twin of `NotchBuddy/Sources/App/ReplyAttachment.swift`. Both
 * sides are dumped and diffed by `scripts/test-reply-attachments.sh`, so a
 * kind, a limit or a MIME type gained on one side and missed on the other is a
 * failing build rather than a file the other platform quietly refuses.
 *
 * Pure over its arguments, exactly as the Swift is: nothing here touches the
 * filesystem or Tauri.
 */

export type AttachmentKind = "image" | "pdf" | "document" | "other";

export interface ReplyAttachment {
  id: string;
  /** Absolute path on disk, as Rust reported it. */
  path: string;
  name: string;
  byteCount: number;
  kind: AttachmentKind;
}

/** A file offered to the reply box, with its size already read. */
export interface AttachmentCandidate {
  path: string;
  byteCount: number;
  /** False for a directory. The caller knows; this module does not look. */
  isRegularFile?: boolean;
}

export const AttachmentLimits = {
  maxCount: 10,
  maxBytesPerFile: 20 * 1024 * 1024,
  maxTotalBytes: 50 * 1024 * 1024,
} as const;

const IMAGE_EXTENSIONS = [
  "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp",
];

const DOCUMENT_EXTENSIONS = [
  "txt", "md", "csv", "json", "yaml", "yml", "xml", "rtf",
  "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
];

/** Every extension either side claims, for the parity dump. */
export const KNOWN_EXTENSIONS = [...IMAGE_EXTENSIONS, "pdf", ...DOCUMENT_EXTENSIONS];

export function extensionOf(pathOrName: string): string {
  const leaf = baseName(pathOrName);
  const dot = leaf.lastIndexOf(".");
  return dot <= 0 ? "" : leaf.slice(dot + 1);
}

/** The last path component, for either separator — the app runs on both. */
export function baseName(path: string): string {
  const cut = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"));
  return cut < 0 ? path : path.slice(cut + 1);
}

export function kindFor(extension: string): AttachmentKind {
  const ext = extension.toLowerCase();
  if (IMAGE_EXTENSIONS.includes(ext)) return "image";
  if (ext === "pdf") return "pdf";
  if (DOCUMENT_EXTENSIONS.includes(ext)) return "document";
  return "other";
}

/** The handful worth naming. Anything else is bytes, and says so. */
export function mimeTypeFor(extension: string): string {
  switch (extension.toLowerCase()) {
    case "jpg": case "jpeg": return "image/jpeg";
    case "png":  return "image/png";
    case "gif":  return "image/gif";
    case "webp": return "image/webp";
    case "heic": return "image/heic";
    case "heif": return "image/heif";
    case "tiff": return "image/tiff";
    case "bmp":  return "image/bmp";
    case "pdf":  return "application/pdf";
    case "txt":  return "text/plain";
    case "md":   return "text/markdown";
    case "csv":  return "text/csv";
    case "json": return "application/json";
    case "xml":  return "application/xml";
    case "yaml": case "yml": return "application/yaml";
    case "rtf":  return "application/rtf";
    case "zip":  return "application/zip";
    default:     return "application/octet-stream";
  }
}

/**
 * Rounded the way a file size is spoken rather than computed — the chip has
 * room for "2.4 MB" and none for "2,411,724 bytes".
 */
export function sizeLabel(byteCount: number): string {
  const units = ["B", "KB", "MB", "GB"];
  let value = byteCount;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  if (unit === 0) return `${byteCount} B`;
  return `${value < 10 ? value.toFixed(1) : value.toFixed(0)} ${units[unit]}`;
}

export type AttachmentRejection =
  | { reason: "tooMany" }
  | { reason: "tooLarge"; name: string }
  | { reason: "wouldExceedTotal"; name: string }
  | { reason: "duplicate"; name: string }
  | { reason: "notAFile"; name: string };

/** Why a file was turned away, in words the card shows unchanged. */
export function rejectionMessage(rejection: AttachmentRejection): string {
  switch (rejection.reason) {
    case "tooMany":
      return `That is more than ${AttachmentLimits.maxCount} files.`;
    case "tooLarge":
      return `${rejection.name} is over 20 MB.`;
    case "wouldExceedTotal":
      return `${rejection.name} would take the reply over 50 MB.`;
    case "duplicate":
      return `${rejection.name} is already attached.`;
    case "notAFile":
      return `${rejection.name} is a folder.`;
  }
}

export interface IntakeResult {
  accepted: ReplyAttachment[];
  rejected: AttachmentRejection[];
}

let counter = 0;
function nextId(): string {
  counter += 1;
  return `att-${counter}`;
}

/**
 * Decides which of `candidates` join `existing`.
 *
 * Order matters and is deliberate, and matches the Swift: a file is checked
 * against what is already staged *and* against the ones accepted earlier in
 * the same drop, so dropping the same file twice in one gesture is caught.
 */
export function acceptAttachments(
  candidates: AttachmentCandidate[],
  existing: ReplyAttachment[],
  ids: string[] = [],
): IntakeResult {
  const result: IntakeResult = { accepted: [], rejected: [] };
  const staged = [...existing];
  let total = existing.reduce((sum, a) => sum + a.byteCount, 0);
  let idIndex = 0;

  for (const candidate of candidates) {
    const name = baseName(candidate.path);

    if (candidate.isRegularFile === false) {
      result.rejected.push({ reason: "notAFile", name });
      continue;
    }
    if (staged.length >= AttachmentLimits.maxCount) {
      // One complaint, however many are left.
      if (!result.rejected.some((r) => r.reason === "tooMany")) {
        result.rejected.push({ reason: "tooMany" });
      }
      continue;
    }
    if (staged.some((a) => a.path === candidate.path)) {
      result.rejected.push({ reason: "duplicate", name });
      continue;
    }
    if (candidate.byteCount > AttachmentLimits.maxBytesPerFile) {
      result.rejected.push({ reason: "tooLarge", name });
      continue;
    }
    if (total + candidate.byteCount > AttachmentLimits.maxTotalBytes) {
      result.rejected.push({ reason: "wouldExceedTotal", name });
      continue;
    }

    const attachment: ReplyAttachment = {
      id: ids[idIndex++] ?? nextId(),
      path: candidate.path,
      name,
      byteCount: candidate.byteCount,
      kind: kindFor(extensionOf(candidate.path)),
    };
    staged.push(attachment);
    result.accepted.push(attachment);
    total += candidate.byteCount;
  }

  return result;
}
