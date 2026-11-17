// The Windows and Linux close shortcut, as the settings window records it.
//
// What comes out is handed straight to the global-shortcut plugin, which takes
// those keys away from every other app. So the two failures that matter are a
// shortcut that steals ordinary typing (Shift+X, or a bare X) and one the
// parser cannot read, which would leave a setting that does nothing. Both are
// asserted here, where no window and no keyboard are needed.
//
// Run by scripts/test-close-shortcut.sh. The Mac's rules are in
// tests/CloseHotKeyTests.swift.

import { acceleratorFrom, shortcutLabel, type ShortcutKey } from "../windows/src/core/shortcut.ts";

let failures = 0;
function check(condition: boolean, what: string) {
  console.log(`  ${condition ? "✓" : "✗"} ${what}`);
  if (!condition) failures++;
}

function key(code: string, mods: Partial<Omit<ShortcutKey, "code">> = {}): ShortcutKey {
  return { code, ctrlKey: false, altKey: false, shiftKey: false, metaKey: false, ...mods };
}

// ── What spells a shortcut ────────────────────────────────────────────────────

check(acceleratorFrom(key("KeyX", { ctrlKey: true, altKey: true })) === "Ctrl+Alt+X",
      "Ctrl+Alt+X, the default, comes out as the default is stored");
check(acceleratorFrom(key("Digit5", { ctrlKey: true, shiftKey: true })) === "Ctrl+Shift+5",
      "digits lose their prefix");
check(acceleratorFrom(key("F9", { altKey: true })) === "Alt+F9", "function keys keep their name");
check(acceleratorFrom(key("Space", { metaKey: true })) === "Super+Space",
      "the Windows key is Super, which is what the parser reads");
check(acceleratorFrom(key("KeyQ", { ctrlKey: true, altKey: true, shiftKey: true, metaKey: true }))
        === "Ctrl+Alt+Shift+Super+Q",
      "all four modifiers, in one fixed order whatever order they were pressed in");

// ── What does not ─────────────────────────────────────────────────────────────

check(acceleratorFrom(key("KeyX")) === null, "a bare letter is refused: it would take the letter");
check(acceleratorFrom(key("KeyX", { shiftKey: true })) === null,
      "Shift alone is refused: it would take the capital");
check(acceleratorFrom(key("ControlLeft", { ctrlKey: true })) === null,
      "a modifier on its own is the chord still being held, not a shortcut");
check(acceleratorFrom(key("AltRight", { ctrlKey: true, altKey: true })) === null,
      "AltGr arrives as Ctrl+AltRight and is still just modifiers");
check(acceleratorFrom(key("Unidentified", { ctrlKey: true })) === null,
      "a key the browser could not name is refused rather than stored");

// ── How it reads ──────────────────────────────────────────────────────────────

check(shortcutLabel("Ctrl+Alt+X") === "Ctrl + Alt + X", "the label spaces the parts out");
check(shortcutLabel("Super+Space") === "Win + Space", "and calls the Windows key Win");

console.log(failures === 0 ? "\nAll close-shortcut checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
