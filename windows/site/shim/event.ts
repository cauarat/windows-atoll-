// Stand-in for @tauri-apps/api/event on the download page.
//
// The island listens for its events exactly as it does in the app; here the
// demo is what emits them, instead of Rust.

type Handler = (event: { event: string; id: number; payload: unknown }) => void;

const handlers = new Map<string, Set<Handler>>();
let nextId = 1;

export async function listen<T>(name: string, handler: (event: { event: string; id: number; payload: T }) => void) {
  let set = handlers.get(name);
  if (!set) handlers.set(name, (set = new Set()));
  set.add(handler as Handler);
  return () => { set!.delete(handler as Handler); };
}

export async function once<T>(name: string, handler: (event: { event: string; id: number; payload: T }) => void) {
  const off = await listen<T>(name, (e) => { off(); handler(e); });
  return off;
}

export function emitLocal(name: string, payload: unknown) {
  handlers.get(name)?.forEach((h) => h({ event: name, id: nextId++, payload }));
}

export async function emit(name: string, payload?: unknown) {
  emitLocal(name, payload);
}

export type UnlistenFn = () => void;
