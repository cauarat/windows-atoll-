// Stand-in for @tauri-apps/plugin-dialog: the demo never opens a file picker.
export async function open() { return null; }
export async function save() { return null; }
export async function message() { return undefined; }
export async function ask() { return false; }
export async function confirm() { return false; }
