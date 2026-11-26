// Imported before the app: from here on the island believes it runs inside
// Notchy, and every Tauri call goes to site/shim instead of nowhere.
import { setLanguage } from "../src/core/i18n";
import { LANG } from "./data";

(window as any).__TAURI_INTERNALS__ = {};

// The island builds its cards when it is created, before boot says which
// language to speak; in the app the system language is the right guess, on a
// web page it is the visitor's. Say it first, so no card is born in English.
setLanguage(LANG);
