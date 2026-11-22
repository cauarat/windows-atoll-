// Resolves `./owner` to `./owner.ts`, the way Vite does, for a test that loads
// a windows/src module which imports its neighbours without an extension.
//
// Node's own resolver never guesses an extension, so `import "./owner"` from
// windows/src/core/state.ts is a "Cannot find module" under
// --experimental-strip-types. The modules the other parity suites load import
// only types, which are stripped before anything resolves them; state.ts is
// the first with real imports. Registered by tests/extensionless.mjs.

export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context);
  } catch (error) {
    const relative = specifier.startsWith("./") || specifier.startsWith("../");
    if (!relative || /\.[cm]?[jt]s$/.test(specifier)) throw error;
    return nextResolve(`${specifier}.ts`, context);
  }
}
