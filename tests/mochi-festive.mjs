// What both runtimes take for granted about the generated Christmas parts.
// Run by scripts/test-mochi-festive.sh.
import { readFileSync } from 'node:fs';

const ts = readFileSync('windows/src/mochi/festive.generated.ts', 'utf8');
const swift = readFileSync('NotchBuddy/Sources/App/MochiFestiveData.swift', 'utf8');
const i18n = JSON.parse(readFileSync('i18n/catalog.json', 'utf8'));

let failed = 0;
const check = (ok, what) => { if (!ok) { failed++; console.error('  ✗ ' + what); } };

const tsJson = ts.match(/export const FESTIVE_JSON = '(.*)';/)?.[1];
const swiftJson = swift.match(/#"""\n(.*)\n"""#/)?.[1];
check(!!tsJson && !!swiftJson, 'both generated files carry the JSON');
check(tsJson === swiftJson, 'Swift and TypeScript carry the same bytes');
const data = JSON.parse(tsJson ?? '{}');

const BODIES = ['classic', 'round', 'boxy', 'fluffy', 'pointy', 'heart', 'frog', 'ato'];
check(JSON.stringify(Object.keys(data.bodies)) === JSON.stringify(BODIES), 'every body, and Ato, has an entry');

const { heads, eyes, textures, extras, presets } = data.catalog;
const ids = (list) => list.map((x) => x[0]);
for (const [list, n] of [[heads, 11], [eyes, 9], [textures, 7], [extras, 8]]) {
  check(list.length === n && new Set(ids(list)).size === n, `a catalogue list has ${n} distinct ids`);
}

// Names are the catalogue keys: translated where drawn, so each needs a row.
const UI = ['Christmas', 'Until January 6', 'Ready-made', 'Head', 'Eyes', 'Texture', 'Extra', 'None'];
for (const name of [...heads, ...eyes, ...textures, ...extras].map((x) => x[1]).concat(presets.map((p) => p.name), UI)) {
  check(typeof i18n[name] === 'object' && i18n[name].es && i18n[name]['pt-BR'], `"${name}" is in i18n/catalog.json`);
}

// A preset only points at things that exist, and between them the presets
// show every part at least once — the picker's own tiles are the only other
// place a part is ever seen.
check(presets.length === 12 && new Set(presets.map((p) => p.id)).size === 12, 'twelve distinct presets');
const used = { head: new Set(), eyes: new Set(), texture: new Set(), extra: new Set() };
for (const p of presets) {
  for (const [key, list] of [['head', heads], ['eyes', eyes], ['texture', textures], ['extra', extras]]) {
    if (p[key] !== null) { check(ids(list).includes(p[key]), `preset ${p.id}: ${key} "${p[key]}" exists`); used[key].add(p[key]); }
  }
  check(p.head !== null || p.eyes !== null || p.texture !== null || p.extra !== null, `preset ${p.id} wears something`);
}
for (const [key, list] of [['head', heads], ['eyes', eyes], ['texture', textures], ['extra', extras]]) {
  for (const id of ids(list)) {
    if (key === 'eyes' && (id === 'treeGlasses' || id === 'wreathGlasses')) continue;   // offered as parts only
    check(used[key].has(id), `${key} "${id}" appears in a preset`);
  }
}

// The paths: only the five commands the Swift parser reads, absolute, finite.
const PATH = /^(?:[MLQC](?:-?\d+(?:\.\d+)?)(?: -?\d+(?:\.\d+)?)*|Z)+$/;
const TOKEN = /^(?:#[0-9A-Fa-f]{6}|@skin:\d+(?:\.\d+)?|@ink|@glint|@flake|@flakeEdge)$/;
const ANIM = new Set(['bulbA', 'bulbB', 'glowA', 'glowB', 'lit', 'shineA', 'shineB']);
let prims = 0;
function each(list, where, clipped) {
  check(Array.isArray(list), `${where} is a list`);
  for (const p of list ?? []) {
    prims++;
    check(PATH.test(p.d), `${where}: a path uses only M L Q C Z`);
    check(p.f !== undefined || p.s !== undefined, `${where}: a prim paints something`);
    if (p.f !== undefined) check(TOKEN.test(p.f), `${where}: fill "${p.f}" is a colour or a token`);
    if (p.s !== undefined) check(TOKEN.test(p.s) && p.w > 0, `${where}: stroke "${p.s}" has a colour and a width`);
    if (p.o !== undefined) check(p.o > 0 && p.o < 1, `${where}: opacity is between 0 and 1`);
    if (p.k !== undefined) check(ANIM.has(p.k), `${where}: animation "${p.k}" is one both runtimes know`);
    if (clipped) check(p.c === 1, `${where}: a texture is clipped to the body`);
  }
}
for (const body of BODIES) {
  const b = data.bodies[body] ?? {};
  check(PATH.test(b.clip ?? ''), `${body}: the clip is a path`);
  check(b.eye && b.eye.x > 0 && b.eye.s > 0, `${body}: knows where its eyes rest`);
  for (const id of ids(heads)) { each(b.heads?.[id]?.b, `${body}/heads/${id}/b`); each(b.heads?.[id]?.f, `${body}/heads/${id}/f`); check((b.heads?.[id]?.b.length ?? 0) + (b.heads?.[id]?.f.length ?? 0) > 0, `${body}/heads/${id} draws something`); }
  for (const id of ids(eyes)) { each(b.eyes?.[id]?.l, `${body}/eyes/${id}/l`); each(b.eyes?.[id]?.r, `${body}/eyes/${id}/r`); each(b.eyes?.[id]?.over, `${body}/eyes/${id}/over`); check((b.eyes?.[id]?.l.length ?? 0) > 0 && (b.eyes?.[id]?.r.length ?? 0) > 0, `${body}/eyes/${id} has two eyes`); }
  for (const id of ids(textures)) { each(b.textures?.[id], `${body}/textures/${id}`, true); check((b.textures?.[id]?.length ?? 0) > 0, `${body}/textures/${id} draws something`); }
  for (const id of ids(extras)) { each(b.extras?.[id]?.a, `${body}/extras/${id}/a`); each(b.extras?.[id]?.z, `${body}/extras/${id}/z`); check((b.extras?.[id]?.a.length ?? 0) + (b.extras?.[id]?.z.length ?? 0) > 0, `${body}/extras/${id} draws something`); }
}

if (failed) { console.error(`\n  ${failed} festive check(s) failed`); process.exit(1); }
console.log(`  ${BODIES.length} bodies × ${heads.length + eyes.length + textures.length + extras.length} parts, ${prims} prims: all drawable on both platforms`);
