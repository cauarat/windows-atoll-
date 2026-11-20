// `node --import ./tests/extensionless.mjs …` — lets a parity test load
// windows/src modules that import their neighbours without an extension. See
// tests/extensionless-hooks.mjs.

import { register } from "node:module";

register("./extensionless-hooks.mjs", import.meta.url);
