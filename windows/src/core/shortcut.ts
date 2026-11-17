// The close shortcut, turned from a key press in the settings window into the
// string Rust registers ("Ctrl+Alt+X") — see src-tauri/src/shortcut.rs.
//
// Read from `code`, not `key`: `code` is the physical key, the same one the
// system shortcut fires on, whatever the layout and whatever Alt does to the
// character. An AZERTY "A" is reported as KeyQ, and that is the key a global
// shortcut will actually catch.

/** The keys that only modify, and so cannot end a shortcut on their own. */
const MODIFIER_CODES = new Set([
  "ControlLeft", "ControlRight", "AltLeft", "AltRight",
  "ShiftLeft", "ShiftRight", "MetaLeft", "MetaRight", "OSLeft", "OSRight",
]);

/** The part of a key event this needs, so tests can build one by hand. */
export interface ShortcutKey {
  code: string;
  ctrlKey: boolean;
  altKey: boolean;
  shiftKey: boolean;
  metaKey: boolean;
}

/**
 * The shortcut a key press spells, or null when it does not spell one yet.
 *
 * Null for a bare modifier (the user is still holding the chord down) and for
 * a key without Ctrl, Alt or the Windows key: Shift alone would take a capital
 * letter away from every other app, and no modifier at all would take the
 * letter itself.
 */
export function acceleratorFrom(e: ShortcutKey): string | null {
  if (MODIFIER_CODES.has(e.code)) return null;
  if (!e.ctrlKey && !e.altKey && !e.metaKey) return null;
  const key = keyName(e.code);
  if (!key) return null;
  const parts: string[] = [];
  if (e.ctrlKey) parts.push("Ctrl");
  if (e.altKey) parts.push("Alt");
  if (e.shiftKey) parts.push("Shift");
  if (e.metaKey) parts.push("Super");
  parts.push(key);
  return parts.join("+");
}

/**
 * The key's name as the shortcut parser reads it. Letters and digits drop the
 * prefix the DOM gives them; every other code (F5, Space, Comma, ArrowUp) is
 * already the name the parser expects.
 */
function keyName(code: string): string | null {
  if (!code || code === "Unidentified") return null;
  const letter = /^Key([A-Z])$/.exec(code);
  if (letter) return letter[1];
  const digit = /^Digit([0-9])$/.exec(code);
  if (digit) return digit[1];
  return code;
}

/** How the stored shortcut reads in the settings window: the Windows key is
 *  "Win" there, whatever the parser calls it. */
export function shortcutLabel(accelerator: string): string {
  return accelerator.split("+").map((p) => (p === "Super" ? "Win" : p)).join(" + ");
}
