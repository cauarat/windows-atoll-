#!/usr/bin/env node
// Draws everything a Mochi can wear at Christmas, once, for both platforms.
//
// Run it with `node scripts/generate-mochi-festive.mjs --write` and it rewrites
// NotchBuddy/Sources/App/MochiFestiveData.swift,
// windows/src/mochi/festive.generated.ts and Android's assets/festive.json.
// Without --write it only checks that all three are current and exits 1 if one
// is stale, the way generate-i18n does.
//
// Why generate and not draw at runtime: a hat has to sit on seven differently
// shaped heads and on Ato's orb, and a beard has to follow each chin. That is
// geometry worked out against the body tables — about 600 lines of it — and
// writing it twice, in Swift and in TypeScript, is two chances for a Santa hat
// that floats on one platform. So it is worked out here, per body, and each
// engine is left with the one job it cannot share: putting paths on screen.
//
// The output is one JSON document, the same bytes on both sides:
//
//   catalog   heads, eyes, textures, extras — [id, English name] in picker
//             order — and the ready-made presets. Names stay in English: they
//             are the i18n catalogue keys, translated where they are drawn.
//   bodies    one entry per body ("classic", the six shapes, and "ato"), each:
//               eye       where an eye sits at rest and how big it is
//               clip      the body outline, for the engines that want it
//               heads     id -> { b: behind the body, f: in front }
//               eyes      id -> { l: left eye, r: right eye, over: on top of both }
//               textures  id -> prims, all clipped to the body
//               extras    id -> { a: over the face, z: over everything }
//
// A prim is { d, f, s, w, o, c, k }: an SVG path made only of M, L, Q, C and Z;
// fill; stroke and its width (always round caps and joins); opacity when not 1;
// c: 1 when it is clipped to the body; k when it is lit (below). Coordinates
// are the engine's own body frame — origin at the body centre, y down — at
// R = 100, so drawing is "scale by R / 100".
//
// Colours that depend on what is wearing the part are tokens:
//   @skin:K     the body's colour times K (elf ears are made of Mochi)
//   @ink        the eye ink; white on Ato, whose face is white on blue
//   @glint      white; Ato's blue on Ato
//   @flake      the snowflake eye: frost blue on a pale body, white otherwise
//   @flakeEdge  a blue edge under a white flake on a frosted pale body, and
//               nothing at all anywhere else
//
// k names what animates, as an opacity over time t in seconds, c(p) being
// 0.5 - 0.5 * cos(2 * pi * t / p):
//   bulbA 1 -> 0.3 and bulbB 0.3 -> 1, glowA 0.3 -> 0 and glowB 0 -> 0.3:
//         the string lights, a 2.2 s cycle that holds each state and eases
//         between them (see `lit` in either runtime)
//   lit    0.6 + 0.4 * c(1.8)     the tree star's core
//   shineA 0.08 + 0.32 * c(1.8)   its wide glow
//   shineB 0.28 + 0.52 * c(1.8)   its tight glow

import { readFileSync, writeFileSync } from 'node:fs';

const CATALOG = {
  heads: [['santaHat', 'Santa hat'], ['elfHat', 'Elf hat'], ['elfEars', 'Elf ears'], ['antlers', 'Reindeer antlers'], ['beanie', 'Knit beanie'], ['topHat', 'Top hat'], ['treeStar', 'Tree star'], ['holly', 'Holly'], ['halo', 'Halo'], ['earmuffs', 'Earmuffs'], ['giftBow', 'Gift bow']],
  eyes: [['starEye', 'Star eyes'], ['snowflake', 'Snowflake eyes'], ['coal', 'Coal eyes'], ['bauble', 'Bauble eyes'], ['peppermint', 'Peppermint eyes'], ['bulb', 'Light bulb eyes'], ['jolly', 'Jolly eyes'], ['treeGlasses', 'Tree glasses'], ['wreathGlasses', 'Wreath glasses']],
  textures: [['sweater', 'Sweater'], ['candyCane', 'Candy cane'], ['snowCap', 'Snow dusting'], ['gingerbread', 'Gingerbread'], ['giftWrap', 'Gift wrap'], ['frost', 'Frost'], ['snowyPines', 'Snowy pines']],
  extras: [['beard', 'Santa beard'], ['lights', 'String lights'], ['scarf', 'Scarf'], ['snowfall', 'Falling snow'], ['redNose', 'Red nose'], ['wreath', 'Wreath'], ['bell', 'Bell'], ['carrot', 'Carrot nose']],
  presets: [
    { id: 'santa', name: 'Santa', head: 'santaHat', eyes: 'jolly', texture: null, extra: 'beard' },
    { id: 'reindeer', name: 'Reindeer', head: 'antlers', eyes: null, texture: 'snowCap', extra: 'redNose' },
    { id: 'elf', name: 'Elf', head: 'elfHat', eyes: 'starEye', texture: null, extra: 'bell' },
    { id: 'snowman', name: 'Snowman', head: 'topHat', eyes: 'coal', texture: null, extra: 'carrot' },
    { id: 'cookie', name: 'Cookie', head: 'holly', eyes: null, texture: 'gingerbread', extra: null },
    { id: 'tree', name: 'Little tree', head: 'treeStar', eyes: 'bauble', texture: null, extra: 'lights' },
    { id: 'gift', name: 'Gift', head: 'giftBow', eyes: null, texture: 'giftWrap', extra: null },
    { id: 'angel', name: 'Angel', head: 'halo', eyes: 'jolly', texture: null, extra: 'snowfall' },
    { id: 'mint', name: 'Peppermint', head: 'elfEars', eyes: 'peppermint', texture: 'candyCane', extra: 'scarf' },
    { id: 'frosty', name: 'Frosty', head: 'earmuffs', eyes: 'snowflake', texture: 'frost', extra: null },
    { id: 'knit', name: 'Knit', head: 'beanie', eyes: null, texture: 'sweater', extra: null },
    { id: 'cozy', name: 'Cozy', head: 'santaHat', eyes: 'bulb', texture: 'snowyPines', extra: 'wreath' },
  ],
};

// ---------------------------------------------------------------------------
// The body tables, lifted from the generated shape.ts so a hat is fitted to
// exactly the head the engine draws.

const SH = {};
{
  const src = readFileSync('windows/src/mochi/shape.ts', 'utf8');
  const nums = (s) => s.split(',').map((v) => Number(v.trim())).filter((v) => !Number.isNaN(v));
  const re = /(\w+): \{\s*outline72: \[([^\]]*)\],[\s\S]*?sockets: \[([\s\S]*?)\],\s*anchor24: \[([^\]]*)\],\s*rxK: ([-\d.]+), ryK: ([-\d.]+)[\s\S]*?eyeSp: ([-\d.]+), eyeP: ([-\d.]+)/g;
  for (let m; (m = re.exec(src));) {
    const s = [...m[3].matchAll(/x: ([-\d.]+), y: ([-\d.]+), r: ([-\d.]+)/g)].map((k) => ({ x: +k[1], y: +k[2], r: +k[3] }));
    SH[m[1]] = { o: nums(m[2]), a: nums(m[4]), rx: +m[5], ry: +m[6], es: +m[7], ep: +m[8], s };
  }
  for (const k of ['round', 'boxy', 'fluffy', 'pointy', 'heart', 'frog']) {
    if (!SH[k] || SH[k].o.length !== 72 || SH[k].a.length !== 24) throw new Error('shape table not read: ' + k);
  }
}

// ---------------------------------------------------------------------------
// The drawing. Plain functions over a path builder that bakes its transform
// into the numbers, so every part comes out as flat path strings.

function makeKit(SH) {
  var PI = Math.PI, R = 100, DEG = PI / 180;
  var INK = '#1A1412', RED = '#E8364F', RED_D = '#C22A43', GREEN = '#2FBF7F', GREEN_D = '#1E9E63',
    GOLD = '#F7B32B', GOLD_D = '#D99415', GOLD_L = '#FFE08A', WHITE = '#FFFFFF', SHADE = '#C3D0E2',
    PINK = '#FF7896', BROWN = '#9A6B3F', DARK = '#1F2228', BLUE = '#3B9EFF', BLUE_D = '#1F6FD0',
    YELLOW = '#FFC83D', GINGER = '#B5743A';

  function fx(n) { var v = Math.round(n * 10) / 10; return String(v === 0 ? 0 : v); }
  function mat(tx, ty, rot, sx, sy) {
    var c = Math.cos(rot), s = Math.sin(rot);
    return [c * sx, s * sx, -s * sy, c * sy, tx, ty];
  }
  function clamp(v, a, b) { return Math.min(Math.max(v, a), b); }

  // A path that bakes its transform into the numbers, so one flat list of
  // <path> elements can describe everything a Mochi wears.
  function Path(m) { this.s = []; this.m = m || null; }
  var PP = Path.prototype;
  PP.p = function (x, y) {
    var m = this.m;
    if (!m) return fx(x) + ' ' + fx(y);
    return fx(m[0] * x + m[2] * y + m[4]) + ' ' + fx(m[1] * x + m[3] * y + m[5]);
  };
  PP.M = function (x, y) { this.s.push('M' + this.p(x, y)); return this; };
  PP.L = function (x, y) { this.s.push('L' + this.p(x, y)); return this; };
  PP.Q = function (a, b, x, y) { this.s.push('Q' + this.p(a, b) + ' ' + this.p(x, y)); return this; };
  PP.C = function (a, b, c, d, x, y) { this.s.push('C' + this.p(a, b) + ' ' + this.p(c, d) + ' ' + this.p(x, y)); return this; };
  PP.Z = function () { this.s.push('Z'); return this; };
  PP.d = function () { return this.s.join(''); };
  PP.ell = function (cx, cy, rx, ry) {
    var k = 0.5523;
    return this.M(cx + rx, cy)
      .C(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry)
      .C(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy)
      .C(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry)
      .C(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy).Z();
  };
  PP.rect = function (x, y, w, h) { return this.M(x, y).L(x + w, y).L(x + w, y + h).L(x, y + h).Z(); };
  PP.rr = function (x, y, w, h, r) {
    return this.M(x + r, y).L(x + w - r, y).Q(x + w, y, x + w, y + r).L(x + w, y + h - r)
      .Q(x + w, y + h, x + w - r, y + h).L(x + r, y + h).Q(x, y + h, x, y + h - r).L(x, y + r).Q(x, y, x + r, y).Z();
  };
  PP.poly = function (pts) {
    this.M(pts[0][0], pts[0][1]);
    for (var i = 1; i < pts.length; i++) this.L(pts[i][0], pts[i][1]);
    return this.Z();
  };
  PP.line = function (pts) {
    this.M(pts[0][0], pts[0][1]);
    for (var i = 1; i < pts.length; i++) this.L(pts[i][0], pts[i][1]);
    return this;
  };
  // A zero-length stroke with round caps draws a dot: the cheapest circle there is.
  PP.dot = function (x, y) { return this.M(x, y).L(x + 0.1, y); };
  PP.smooth = function (pts, closed, cont) {
    var n = pts.length, i, p0, p1, p2, p3;
    function at(k) { return closed ? pts[((k % n) + n) % n] : pts[Math.max(0, Math.min(n - 1, k))]; }
    if (cont) this.L(pts[0][0], pts[0][1]); else this.M(pts[0][0], pts[0][1]);
    var last = closed ? n : n - 1;
    for (i = 0; i < last; i++) {
      p0 = at(i - 1); p1 = at(i); p2 = at(i + 1); p3 = at(i + 2);
      this.C(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6,
        p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6, p2[0], p2[1]);
    }
    if (closed) this.Z();
    return this;
  };
  PP.star = function (cx, cy, ro, ri, n, rot) {
    var pts = [], i, a, r;
    for (i = 0; i < n * 2; i++) {
      a = (rot || 0) - PI / 2 + i * PI / n; r = i % 2 ? ri : ro;
      pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
    return this.poly(pts);
  };
  PP.flake = function (cx, cy, r, ticks) {
    var k, a, c, s, t, b;
    for (k = 0; k < 3; k++) {
      a = PI / 2 + k * PI / 3; c = Math.cos(a); s = Math.sin(a);
      this.M(cx - r * c, cy - r * s).L(cx + r * c, cy + r * s);
    }
    if (ticks) {
      for (k = 0; k < 6; k++) {
        a = PI / 2 + k * PI / 3; c = Math.cos(a); s = Math.sin(a);
        b = [cx + 0.56 * r * c, cy + 0.56 * r * s];
        for (t = -1; t <= 1; t += 2) {
          this.M(b[0], b[1]).L(b[0] + 0.36 * r * Math.cos(a + t * 0.95), b[1] + 0.36 * r * Math.sin(a + t * 0.95));
        }
      }
    }
    return this;
  };

  function F(path, fill, op, clip, k) { return { d: path.d(), f: fill, s: 'none', w: 0, o: op == null ? 1 : op, c: !!clip, k: k || '' }; }
  function S(path, stroke, w, op, clip, k) { return { d: path.d(), f: 'none', s: stroke, w: w, o: op == null ? 1 : op, c: !!clip, k: k || '' }; }
  // The body's own colour is only known when drawn, so parts made of Mochi
  // carry a token and the engine multiplies its colour in.
  function shadeHex(hex, k) { return '@skin:' + k; }

  // Ato's orb, from design/ato/actuar-bot-v3.js: three wavy discs (orange
  // behind, cyan, blue in front) at 88% opacity, frozen at the engine's rest
  // time T = 1.3. Radii are in the engine's own units; 196 of them are one R.
  var ATO = [
    { R: 196, A: 15.63, n: 5, ph: 0.455, rot: 9.1, f: '#FB5423' },
    { R: 192, A: 11.10, n: 6, ph: 0.745, rot: 10.9, f: '#1FEFFF' },
    { R: 196, A: 12.30, n: 7, ph: 2.7185, rot: 46.4, f: '#1B2FEB' }
  ];
  function atoR(L, th) { return (L.R + L.A * Math.sin(L.n * (th - L.rot * DEG) + L.ph)) / 196; }
  var INKC = '@ink', GLINT = '@glint', FLAKE = '@flake', FLAKE_EDGE = '@flakeEdge';

  function interp(tab) {
    return function (th) {
      var n = tab.length, two = PI * 2, t = ((th % two) + two) % two, f = t / two * n;
      var i = Math.floor(f) % n, a = tab[i], b = tab[(i + 1) % n];
      return a + (b - a) * (f - Math.floor(f));
    };
  }

  // The body, read from the same radial tables the app draws.
  function geo(shape) {
    var t = SH[shape], g = {}, i, th;
    if (shape === 'ato') {
      // Eyes: white dots of radius 26 at (+-68, -14) in engine units.
      g.ato = true; g.rx = 1; g.ry = 1; g.es = Math.asin(68 / 196); g.ep = Math.asin(14 / 196); g.sock = []; g.anc = null; g.out = [];
      for (i = 0; i < 72; i++) { th = i / 72 * 2 * PI; g.out.push(Math.max(atoR(ATO[0], th), atoR(ATO[1], th), atoR(ATO[2], th))); }
    } else if (t) {
      g.out = t.o; g.anc = t.a; g.rx = t.rx; g.ry = t.ry; g.es = t.es; g.ep = t.ep; g.sock = t.s || [];
    } else {
      g.rx = 1.14; g.ry = 0.88; g.es = 0.37; g.ep = -0.12; g.sock = []; g.anc = null; g.out = [];
      for (i = 0; i < 72; i++) {
        th = i / 72 * 2 * PI;
        g.out.push(1 / Math.pow(Math.pow(Math.abs(Math.cos(th)) / 1.14, 2.7) + Math.pow(Math.abs(Math.sin(th)) / 0.88, 2.7), 1 / 2.7));
      }
    }
    g.frog = g.sock.length > 0;
    g.rAt = interp(g.out);
    g.aAt = g.anc ? interp(g.anc) : g.rAt;
    g.sp = function (deg, off) { var a = deg * DEG, r = g.rAt(a) * R + (off || 0); return [r * Math.cos(a), r * Math.sin(a)]; };
    g.wp = function (deg, off) { var a = deg * DEG, r = g.aAt(a) * R + (off || 0); return [r * Math.cos(a), r * Math.sin(a)]; };
    g.pts = [];
    for (i = 0; i < 72; i++) { th = i / 72 * 2 * PI; g.pts.push([g.out[i] * R * Math.cos(th), g.out[i] * R * Math.sin(th)]); }
    var all = g.pts.slice();
    g.sock.forEach(function (k) {
      for (var j = 0; j < 24; j++) all.push([(k.x + k.r * Math.cos(j / 24 * 2 * PI)) * R, (k.y + k.r * Math.sin(j / 24 * 2 * PI)) * R]);
    });
    g.minY = all.reduce(function (m, p) { return Math.min(m, p[1]); }, 0);
    g.topY = -(g.aAt(-PI / 2) * R - 3);
    g.botY = g.rAt(PI / 2) * R;
    g.halfW = function (depth) {
      var lim = g.topY + depth, m = 0;
      all.forEach(function (p) { if (p[1] <= lim && Math.abs(p[0]) > m) m = Math.abs(p[0]); });
      return m;
    };
    g.hatW = clamp(g.halfW(24) * 1.05, 46, 80);
    // Where a hat's brim goes: the top of the head, or higher when the eyes
    // are up there too (the frog), so a brim never comes down over them.
    g.hatY = function () { return Math.min(g.topY, g.ey - 18 * g.eyeS - 24); };
    // Where a rigid hat of half-width hw comes to rest: the first level, going
    // down from the very top, at which the head is as wide as the hat. On a
    // dome that is the top; on a point the hat slides down over the tip; on
    // the frog and the heart it rests across the two bumps.
    g.rest = function (hw) {
      var y, lo = 0, hi = 0;
      for (y = g.minY; y < g.minY + 45; y += 1) {
        lo = 0; hi = 0;
        all.forEach(function (p) { if (p[1] <= y) { if (p[0] < lo) lo = p[0]; if (p[0] > hi) hi = p[0]; } });
        if (hi - lo >= 2 * hw) break;
      }
      return { x: (lo + hi) / 2, y: y };
    };
    g.ex = g.frog ? g.sock[1].x * R : Math.sin(g.es) * g.rx * R;
    g.ey = g.frog ? g.sock[1].y * R : -Math.sin(g.ep) * g.ry * R;
    g.fy = g.frog ? -10 : g.ey;
    g.eyeS = g.frog ? 1.5 : (g.ato ? 26 / 196 * 100 / 11.5 : 1);
    // Where a nose sits: just under the eyes. The frog's eyes are up on its
    // bulges, so its nose goes right below them rather than mid-belly.
    g.ny = g.frog ? -34 : g.ey + 26;
    // The engine's headPoint at rest: a point on a sphere, pushed out to the silhouette.
    g.head = function (a0, e0) {
      var hx = Math.sin(a0) * Math.cos(e0) * g.rx * R, hy = -Math.sin(e0) * g.ry * R;
      if (g.anc) {
        var a = Math.atan2(hy, hx);
        var on = Math.sqrt(Math.pow(Math.cos(a) * g.rx * R, 2) + Math.pow(Math.sin(a) * g.ry * R, 2));
        if (on > 0.01) { var k = g.aAt(a) * R / on; hx *= k; hy *= k; }
      }
      return [hx, hy];
    };
    return g;
  }

  // ── Head ─────────────────────────────────────────────────────────────────

  function earPts(m, sc, dy) {
    return new Path(m).M(-32 * sc, 18 * sc + dy).Q(-28 * sc, -38 * sc + dy, 0, -80 * sc + dy)
      .Q(28 * sc, -38 * sc + dy, 32 * sc, 18 * sc + dy).Z();
  }

  function elfEars(g, skin) {
    var b = [];
    [1, -1].forEach(function (sd) {
      var P = g.sp(sd > 0 ? -22 : -158, -12), m = [sd, 0, 0, 1, P[0], P[1]];
      b.push(F(new Path(m).M(-22, 20).Q(34, 20, 86, -44).Q(26, -40, -22, -22).Z(), shadeHex(skin, 0.9)));
      b.push(F(new Path(m).M(-4, 10).Q(26, 10, 60, -26).Q(22, -24, -4, -12).Z(), PINK, 0.5));
    });
    return { b: b, f: [] };
  }

  function santaHat(g) {
    var w = g.hatW, h = 0.9 * w, m = mat(0, g.hatY(), -0.10, 1, 1), f = [], pr = 0.17 * w + 5;
    f.push(F(new Path(m).M(-0.95 * w, 4)
      .C(-0.88 * w, -0.95 * h, -0.10 * w, -1.50 * h, 0.62 * w, -1.22 * h)
      .C(0.92 * w, -1.10 * h, 1.12 * w, -0.92 * h, 1.12 * w, -0.62 * h)
      .C(1.02 * w, -0.80 * h, 0.86 * w, -0.88 * h, 0.70 * w, -0.84 * h)
      .C(0.84 * w, -0.56 * h, 0.94 * w, -0.28 * h, 0.95 * w, 4).Z(), RED));
    f.push(F(new Path(m).M(0.70 * w, -0.84 * h).C(0.84 * w, -0.56 * h, 0.94 * w, -0.28 * h, 0.95 * w, 4)
      .L(0.56 * w, 4).C(0.62 * w, -0.34 * h, 0.60 * w, -0.62 * h, 0.70 * w, -0.84 * h).Z(), RED_D, 0.6));
    f.push(S(new Path(m).M(-1.02 * w, 17).Q(0, -9, 1.02 * w, 17), SHADE, 26));
    f.push(S(new Path(m).M(-1.02 * w, 12).Q(0, -14, 1.02 * w, 12), WHITE, 26));
    f.push(F(new Path(m).ell(1.12 * w + 2, -0.56 * h + 3, pr, pr), SHADE));
    f.push(F(new Path(m).ell(1.12 * w, -0.56 * h, pr, pr), WHITE));
    return { b: [], f: f };
  }

  function elfHat(g, skin) {
    var w = g.hatW, m = mat(0, g.hatY(), 0.06, 1, 1), f = [], pts = [], j, x;
    f.push(F(new Path(m).M(-0.92 * w, 2).C(-0.86 * w, -0.62 * w, -0.80 * w, -1.08 * w, -0.60 * w, -1.42 * w)
      .C(-0.28 * w, -1.06 * w, 0.62 * w, -0.56 * w, 0.92 * w, 2).Z(), GREEN));
    f.push(F(new Path(m).M(-0.92 * w, 2).C(-0.86 * w, -0.62 * w, -0.80 * w, -1.08 * w, -0.60 * w, -1.42 * w)
      .C(-0.62 * w, -1.0 * w, -0.58 * w, -0.5 * w, -0.50 * w, 2).Z(), GREEN_D, 0.6));
    for (j = 0; j <= 4; j++) { x = -w + j * w / 2; pts.push([x * 1.02, 12 * Math.pow(x / w, 2) - 16]); }
    for (j = 0; j <= 12; j++) { x = w - j * w / 6; pts.push([x * 1.02, 12 * Math.pow(x / w, 2) + (j % 2 ? 22 : 5)]); }
    f.push(F(new Path(m).poly(pts), RED));
    f.push(F(new Path(m).ell(-0.60 * w, -1.42 * w - 4, 9, 9), GOLD));
    f.push(S(new Path(m).dot(-0.60 * w, -1.42 * w - 1), GOLD_D, 5));
    return { b: elfEars(g, skin).b, f: f };
  }

  function antlers(g, skin) {
    var b = [];
    [1, -1].forEach(function (sd) {
      var P = g.sp(sd > 0 ? -38 : -142, -10), m = mat(P[0], P[1], sd * 1.05, 0.62, 0.62);
      b.push(F(earPts(m, 1, 0), shadeHex(skin, 0.86)));
      b.push(F(earPts(m, 0.52, 10), PINK, 0.5));
    });
    [1, -1].forEach(function (sd) {
      var P = g.head(sd * 0.5, 1.12), m = mat(P[0], P[1], sd * 0.22, sd, 1);
      b.push(S(new Path(m).M(0, 18).Q(2, -38, 28, -80).M(6, -30).Q(30, -32, 46, -54).M(16, -58).Q(-2, -68, -6, -90), BROWN, 13));
    });
    return { b: b, f: [] };
  }

  function beanie(g) {
    // The cuff never comes down over the eyes: its lower edge (about yc + 15)
    // stays clear of the top of the eye.
    var eyeTop = g.ey - 18 * g.eyeS, yc = Math.min(g.topY + 36, eyeTop - 17);
    var arc = [], d, p, f = [], j, x, t, Lp, Rp, pomY;
    for (d = -178; d <= -2; d += 4) { p = g.wp(d, 5); if (p[1] <= yc) arc.push(p); }
    var arcTop = arc.reduce(function (m, q) { return Math.min(m, q[1]); }, yc);
    if (arc.length >= 5 && arc[arc.length - 1][0] - arc[0][0] >= 60 && yc - arcTop >= 22) {
      // Pulled down over the head, following its outline.
      Lp = arc[0]; Rp = arc[arc.length - 1]; pomY = g.wp(-90, 5)[1] - 12;
      f.push(F(new Path().M(Lp[0], yc + 2).smooth(arc, false, true).L(Rp[0], yc + 2).Q(0, yc + 14, Lp[0], yc + 2).Z(), BLUE));
    } else {
      // The eyes sit too high for that (the frog's are on top of its head), so
      // the beanie keeps its own dome and rests above them.
      var hw = clamp(g.halfW(24) * 0.75, 40, 62), dh = hw * 0.8;
      Lp = [-hw, yc]; Rp = [hw, yc]; pomY = yc - dh * 0.94 - 10;
      f.push(F(new Path().M(-hw, yc + 2).C(-hw * 1.02, yc - dh * 1.25, hw * 1.02, yc - dh * 1.25, hw, yc + 2).Q(0, yc + 14, -hw, yc + 2).Z(), BLUE));
    }
    var hw = Math.min(-Lp[0], Rp[0]) * 0.7, zz = [];
    for (j = 0; j <= 8; j++) zz.push([-hw + j * hw / 4, yc - 20 + (j % 2 ? -7 : 7)]);
    f.push(S(new Path().line(zz), WHITE, 4));
    f.push(S(new Path().M(Lp[0] + 2, yc + 2).Q(0, yc + 14, Rp[0] - 2, yc + 2), BLUE_D, 18));
    var ribs = new Path();
    for (j = 1; j <= 7; j++) {
      t = j / 8; x = Lp[0] + t * (Rp[0] - Lp[0]);
      var yq = yc + 2 + 6 * (1 - Math.pow(2 * t - 1, 2));
      ribs.M(x, yq - 6).L(x, yq + 6);
    }
    f.push(S(ribs, '#174F99', 2.5, 0.6));
    f.push(F(new Path().ell(2, pomY + 3, 17, 17), SHADE));
    f.push(F(new Path().ell(0, pomY, 17, 17), WHITE));
    return { b: [], f: f };
  }

  function topHat(g) {
    // Upright and centred on the head: no tilt. The size follows the width of
    // this body's head, and the hat rests where the head is as wide as its crown.
    var w = clamp(g.halfW(24) * 0.95, 44, 66), c = 0.62 * w, r = g.rest(0.8 * c), f = [];
    // Stays on the face's axis; a lopsided top (the fluffy one) only nudges it.
    var m = mat(clamp(r.x * 0.4, -6, 6), r.y + 1, 0, 1, 1);
    f.push(F(new Path(m).rr(-c, -1.02 * w, 2 * c, 1.02 * w, 6), DARK));
    f.push(F(new Path(m).rect(-c, -0.36 * w, 2 * c, 0.20 * w), RED));
    f.push(F(new Path(m).rr(-c + 0.12 * w, -0.94 * w, 0.12 * w, 0.50 * w, 3), '#3A404B'));
    f.push(S(new Path(m).M(-1.05 * w, 5).Q(0, -7, 1.05 * w, 5), '#0E1013', 13));
    return { b: [], f: f };
  }

  function treeStar(g) {
    var m = mat(0, g.hatY(), 0, 1, 1);
    return { b: [], f: [
      // Lit from within, with no shape around it: a thin bloom that follows
      // the star's own outline, a brighter body, and a pale core that breathes.
      // The glow is the star's own outline, drawn wide and soft and then
      // tighter and brighter, and both pulse with the core: star-shaped, never a disc.
      S(new Path(m).star(0, -32, 40, 17, 5), '#FFD84A', 20, 0.24, false, 'mn-shine-a'),
      S(new Path(m).star(0, -32, 40, 17, 5), '#FFE27A', 10, 0.5, false, 'mn-shine-b'),
      F(new Path(m).star(0, -32, 40, 17, 5), '#FFC933'),
      F(new Path(m).star(0, -32, 24, 10.5, 5), '#FFF3B0', 1, false, 'mn-lit'),
      F(new Path(m).star(42, -68, 9, 2.9, 4).star(-48, -22, 7, 2.3, 4), GOLD_L)
    ] };
  }

  function leaf(m, L) {
    return new Path(m).M(0, 0)
      .Q(0.15 * L, -0.03 * L, 0.25 * L, -0.24 * L).Q(0.40 * L, -0.13 * L, 0.55 * L, -0.26 * L)
      .Q(0.69 * L, -0.10 * L, 0.82 * L, -0.17 * L).Q(0.90 * L, -0.02 * L, L, 0)
      .Q(0.90 * L, 0.02 * L, 0.82 * L, 0.17 * L).Q(0.69 * L, 0.10 * L, 0.55 * L, 0.26 * L)
      .Q(0.40 * L, 0.13 * L, 0.25 * L, 0.24 * L).Q(0.15 * L, 0.03 * L, 0, 0).Z();
  }

  function holly(g) {
    var P = g.wp(-122, -2), m1 = mat(P[0], P[1], -150 * DEG, 1, 1), m2 = mat(P[0], P[1], -40 * DEG, 1, 1), f = [];
    f.push(F(leaf(m1, 48), GREEN_D));
    f.push(F(leaf(m2, 48), GREEN));
    f.push(S(new Path(m1).M(5, 0).L(40, 0), '#147A4A', 2.5, 0.7));
    f.push(S(new Path(m2).M(5, 0).L(40, 0), '#147A4A', 2.5, 0.7));
    f.push(S(new Path().dot(P[0] - 2, P[1] + 3).dot(P[0] + 10, P[1] - 5).dot(P[0] + 1, P[1] - 11), RED, 17));
    f.push(S(new Path().dot(P[0] - 4.5, P[1] + 0.5).dot(P[0] + 7.5, P[1] - 7.5).dot(P[0] - 1.5, P[1] - 13.5), WHITE, 4, 0.9));
    return { b: [], f: f };
  }

  function halo(g) {
    var cy = g.minY - 30;
    return { b: [], f: [
      // Lit, and still: a faint light around it, a warm bloom hugging the
      // ring, and a pale core so the ring itself reads as glowing.
      F(new Path().ell(0, cy, 60, 23), '#FFD84A', 0.16),
      S(new Path().ell(0, cy, 44, 12), '#FFD84A', 19, 0.38),
      S(new Path().ell(0, cy, 44, 12), GOLD, 8),
      S(new Path().ell(0, cy, 44, 12), '#FFF3B0', 3.5)
    ] };
  }

  function earmuffs(g) {
    var pts = [], d, f = [];
    for (d = -170; d <= -10; d += 8) pts.push(g.wp(d, 9));
    f.push(S(new Path().smooth(pts, false), RED_D, 17));
    [1, -1].forEach(function (sd) {
      var c = g.sp(sd > 0 ? -8 : -172, -2);
      f.push(F(new Path().ell(c[0] + 2, c[1] + 3, 27, 27), SHADE));
      f.push(F(new Path().ell(c[0], c[1], 27, 27), WHITE));
      f.push(F(new Path().ell(c[0], c[1], 15, 15), '#E3EAF3'));
    });
    return { b: [], f: f };
  }

  function giftBow(g) {
    var f = [], y = g.hatY() + 2;
    [1, -1].forEach(function (sd) {
      var m = [sd, 0, 0, 1, 0, y];
      f.push(F(new Path(m).poly([[-10, 2], [-36, 26], [-24, 32], [-18, 24], [-2, 8]]), RED));
      f.push(F(new Path(m).M(0, 0).C(-20, -46, -70, -50, -62, -14).C(-58, 6, -24, 6, 0, 0).Z(), RED));
      f.push(F(new Path(m).M(-14, -8).C(-26, -32, -52, -34, -48, -14).C(-46, -4, -28, -2, -14, -8).Z(), RED_D, 0.6));
    });
    f.push(F(new Path().rr(-11, y - 13, 22, 22, 7), RED_D));
    return { b: [], f: f };
  }

  var HEAD = {
    santaHat: santaHat, elfHat: elfHat, elfEars: elfEars, antlers: antlers, beanie: beanie, topHat: topHat,
    treeStar: treeStar, holly: holly, halo: halo, earmuffs: earmuffs, giftBow: giftBow
  };

  // ── Eyes ─────────────────────────────────────────────────────────────────

  function eyeGlyph(type, cx, cy, s, sd) {
    var out = [], k, a, r, c, p;
    function pol(rad, deg) { return [cx + rad * Math.cos(deg * DEG), cy + rad * Math.sin(deg * DEG)]; }
    if (type === 'starEye') {
      out.push(F(new Path().star(cx, cy, 17 * s, 7.5 * s, 5), INKC));
      out.push(S(new Path().dot(cx - 4 * s, cy - 4 * s), GLINT, 5 * s, 0.95));
    } else if (type === 'snowflake') {
      // The flake takes the colour the body is not: frost blue on a white
      // Mochi, white on a frosted or coloured one (with a blue edge on frost,
      // where white on pale blue would otherwise barely show).
      if (FLAKE_EDGE) out.push(S(new Path().flake(cx, cy, 16 * s, true), FLAKE_EDGE, 6.8 * s));
      out.push(S(new Path().flake(cx, cy, 16 * s, true), FLAKE, 4.2 * s));
    } else if (type === 'coal') {
      var cp = [[0, 13], [55, 11], [100, 14], [160, 11.5], [215, 13.5], [270, 11], [320, 13]].map(function (q) { return pol(q[1] * s, q[0]); });
      out.push(F(new Path().poly(cp), INKC));
      out.push(F(new Path().poly([[cx - 6 * s, cy - 5 * s], [cx - 1 * s, cy - 8 * s], [cx + 1 * s, cy - 3 * s]]), '#6A615B'));
    } else if (type === 'bauble') {
      out.push(F(new Path().ell(cx, cy, 14 * s, 14 * s), sd < 0 ? RED : GREEN_D));
      out.push(F(new Path().rr(cx - 4.5 * s, cy - 19.5 * s, 9 * s, 6.5 * s, 1.5 * s), GOLD));
      out.push(S(new Path().ell(cx, cy - 21.5 * s, 2.2 * s, 2.2 * s), GOLD_D, 1.4 * s));
      out.push(F(new Path().ell(cx - 5 * s, cy - 5 * s, 3.2 * s, 4.4 * s), WHITE, 0.85));
    } else if (type === 'peppermint') {
      r = 14.5 * s;
      out.push(F(new Path().ell(cx, cy, r, r), WHITE));
      p = new Path();
      for (k = 0; k < 3; k++) {
        a = k * 120 + 20;
        var p1 = pol(r, a), p2 = pol(r, a + 60), c1 = pol(r * 0.55, a + 38), c2 = pol(r / Math.cos(30 * DEG), a + 30), c3 = pol(r * 0.55, a + 98);
        p.M(cx, cy).Q(c1[0], c1[1], p1[0], p1[1]).Q(c2[0], c2[1], p2[0], p2[1]).Q(c3[0], c3[1], cx, cy).Z();
      }
      out.push(F(p, RED));
      out.push(S(new Path().ell(cx, cy, r, r), RED_D, 2 * s));
    } else if (type === 'bulb') {
      out.push(S(new Path().dot(cx, cy + 2 * s), YELLOW, 50 * s, 0.22));
      out.push(F(new Path().ell(cx, cy + 3 * s, 10.5 * s, 13.5 * s), YELLOW));
      out.push(S(new Path().ell(cx, cy + 3 * s, 10.5 * s, 13.5 * s), '#B9831A', 1.6 * s));
      out.push(F(new Path().rr(cx - 6 * s, cy - 17 * s, 12 * s, 7.5 * s, 2 * s), '#2A2F38'));
      out.push(F(new Path().ell(cx - 3.5 * s, cy - 1 * s, 2.6 * s, 4 * s), WHITE, 0.9));
    } else if (type === 'jolly') {
      out.push(S(new Path().M(cx - 12 * s, cy + 4 * s).Q(cx, cy - 12 * s, cx + 12 * s, cy + 4 * s), INKC, 5.5 * s));
    } else {
      out.push(F(new Path().ell(cx, cy, 11.5 * s, 11.5 * s), INKC));
    }
    return out;
  }

  // Novelty glasses, worn over the eyes the way the visor and shades are: the
  // pupil stays visible behind a faint lens. The lens is sized from how far
  // apart this body's eyes are, so the pair fits every head.
  function glasses(type, g, s) {
    var px = g.ex, ex = Math.max(g.ex, 25), ey = g.ey, lr = Math.min(ex - 4, 27 * g.eyeS), k = lr / 27, out = [];
    var ps = Math.min(s, lr * 0.5 / 11.5), FRAME = GREEN_D, FRAME_D = '#147A4A';
    function on(p, m) { p.m = m; return p; }
    var eyeL = eyeGlyph('dot', -px, ey, ps, -1), eyeR = eyeGlyph('dot', px, ey, ps, 1);
    // The two temple arms: from the outer edge of each lens back toward the
    // side of the head, rising a little. Clipped to the body, so each one ends
    // at the silhouette, as if it went on round behind.
    var ax = type === 'treeGlasses' ? lr : 0.95 * lr, arms = new Path();
    [1, -1].forEach(function (sd) {
      arms.M(sd * (ex + ax - 2), ey - 0.12 * lr).L(sd * 230, ey - 0.12 * lr - (230 - ex - ax) * 0.10);
    });
    // As thick as the rim it comes off: 0.30 lr on the tree pair, 0.40 lr on the wreaths.
    out.push(S(arms, FRAME, (type === 'treeGlasses' ? 0.30 : 0.40) * lr, 1, true));
    if (type === 'treeGlasses') {
      var rx = lr, ry = lr * 0.82, trees = new Path(), stars = new Path(), gems = new Path();
      var pom = [new Path(), new Path(), new Path()];
      [1, -1].forEach(function (sd) {
        var m = mat(sd * ex, ey - ry * 0.95, sd * 0.10, k, k);
        on(trees, m).poly([[-25, 0], [-14, -15], [-20, -15], [-9, -30], [-14, -30], [-3, -46], [3, -46],
          [14, -30], [9, -30], [20, -15], [14, -15], [25, 0]]);
        on(stars, m).star(0, -50, 8, 3.4, 5);
        on(pom[0], m).dot(1, -31); on(pom[1], m).dot(-7, -17); on(pom[2], m).dot(8, -11);
        [-165, -125, -55, -15].forEach(function (a) { gems.dot(sd * ex + rx * Math.cos(a * DEG), ey + ry * Math.sin(a * DEG)); });
      });
      gems.dot(0, ey - 0.36 * lr);
      out.push(F(new Path().ell(-ex, ey, rx, ry).ell(ex, ey, rx, ry), WHITE, 0.2));
      out.push(F(trees, FRAME));
      out.push(F(stars, GOLD));
      out.push(S(new Path().M(-ex + rx, ey - 0.2 * lr).Q(0, ey - 0.52 * lr, ex - rx, ey - 0.2 * lr), FRAME, 0.22 * lr));
      out.push(S(new Path().ell(-ex, ey, rx, ry).ell(ex, ey, rx, ry), FRAME, 0.30 * lr));
      out.push(S(pom[0], YELLOW, 10 * k)); out.push(S(pom[1], RED, 10 * k)); out.push(S(pom[2], '#7CC7FF', 10 * k));
      out.push(S(gems, '#E3EAF3', 0.15 * lr));
    } else {
      var leaves = new Path(), sprigs = new Path(), loops = new Path(), spots = new Path(), knots = new Path(), i, a;
      [1, -1].forEach(function (sd) {
        for (i = 0; i < 14; i++) { a = i / 14 * 2 * PI; leaves.dot(sd * ex + 1.04 * lr * Math.cos(a), ey + 1.04 * lr * Math.sin(a)); }
        for (i = 0; i < 10; i++) { a = (i + 0.5) / 10 * 2 * PI; sprigs.dot(sd * ex + 0.86 * lr * Math.cos(a), ey + 0.86 * lr * Math.sin(a)); }
        [1, -1].forEach(function (t) {
          var m = mat(sd * ex, ey - 0.98 * lr, 0, t * k * 0.5, k * 0.5);
          on(loops, m).M(0, 0).C(-20, -46, -70, -50, -62, -14).C(-58, 6, -24, 6, 0, 0).Z()
            .poly([[-6, 4], [-34, 32], [-22, 36], [-16, 27], [0, 9]]);
          on(spots, m).dot(-30, -26).dot(-48, -20).dot(-40, -36).dot(-22, -11);
        });
        knots.ell(sd * ex, ey - 0.98 * lr - 2 * k, 5.5 * k, 5.5 * k);
      });
      out.push(F(new Path().ell(-ex, ey, 0.66 * lr, 0.66 * lr).ell(ex, ey, 0.66 * lr, 0.66 * lr), WHITE, 0.2));
      out.push(S(new Path().M(-ex + 0.9 * lr, ey).Q(0, ey - 0.28 * lr, ex - 0.9 * lr, ey), FRAME_D, 0.2 * lr));
      out.push(S(new Path().ell(-ex, ey, 0.86 * lr, 0.86 * lr).ell(ex, ey, 0.86 * lr, 0.86 * lr), FRAME, 0.40 * lr));
      out.push(S(leaves, FRAME, 0.26 * lr));
      out.push(S(sprigs, GREEN, 0.11 * lr));
      out.push(F(loops, RED));
      out.push(S(spots, WHITE, 3.4 * k, 0.95));
      out.push(F(knots, RED_D));
    }
    return { l: eyeL, r: eyeR, over: out };
  }

  function eyes(type, g, mini) {
    var s = Math.min(g.eyeS * (mini ? 1.6 : 1), (g.ex - 2) / 17), out = [];
    if (type === 'treeGlasses' || type === 'wreathGlasses') return glasses(type, g, s);
    if (type === 'jolly') {
      out.push(F(new Path().ell(-(g.frog ? 62 : g.ex + 10), g.frog ? 6 : g.ey + 20, 13, 8)
        .ell(g.frog ? 62 : g.ex + 10, g.frog ? 6 : g.ey + 20, 13, 8), PINK, 0.55, true));
    }
    return { l: eyeGlyph(type, -g.ex, g.ey, s, -1), r: eyeGlyph(type, g.ex, g.ey, s, 1), over: out };
  }

  // ── Texture (clipped to the body) ────────────────────────────────────────

  var ALL = [-200, -260, 400, 520];
  function full() { return new Path().rect(ALL[0], ALL[1], ALL[2], ALL[3]); }
  function zig(y, amp) {
    var pts = [], j;
    for (j = 0; j <= 20; j++) pts.push([-160 + j * 16, y + (j % 2 ? -amp : amp)]);
    return new Path().line(pts);
  }

  var TEX = {
    sweater: function (g) {
      var ys = g.fy + 30, dots = new Path(), x;
      for (x = -152; x <= 152; x += 19) dots.dot(x, ys + 42);
      return [
        F(new Path().rect(-170, ys, 340, 340), RED_D, 1, true),
        F(new Path().rect(-170, ys, 340, 9), '#A8233A', 1, true),
        S(zig(ys + 24, 6), WHITE, 4, 1, true),
        S(dots, WHITE, 7, 1, true),
        F(new Path().rect(-170, ys + 54, 340, 8), GREEN, 1, true),
        S(zig(ys + 76, 5), WHITE, 3.5, 0.9, true)
      ];
    },
    candyCane: function () {
      var wide = new Path(), thin = new Path(), k, a, b;
      for (k = -4; k <= 4; k++) {
        a = k * 62 - 96; b = k * 62 + 96;
        wide.poly([[a - 13, -160], [a + 13, -160], [b + 13, 160], [b - 13, 160]]);
        thin.poly([[a + 22, -160], [a + 28, -160], [b + 28, 160], [b + 22, 160]]);
      }
      return [F(wide, RED, 1, true), F(thin, RED, 0.55, true)];
    },
    snowCap: function (g) {
      var yc = g.minY + 36, j, x;
      function cap(m) {
        var p = new Path(m).M(-170, -260).L(170, -260).L(170, yc);
        for (j = 0, x = 170; j < 10; j++, x -= 34) p.Q(x - 17, yc + (j % 2 ? 22 : 10), x - 34, yc);
        return p.Z();
      }
      var sp = new Path();
      [[-62, 34], [-24, 58], [42, 32], [70, 56], [8, 74], [-84, 60], [88, 22]].forEach(function (q) { sp.dot(q[0], q[1]); });
      return [F(cap(mat(0, 5, 0, 1, 1)), SHADE, 1, true), F(cap(null), WHITE, 1, true), S(sp, WHITE, 7, 0.95, true)];
    },
    gingerbread: function (g) {
      var lo = [], hi = [], d, j = 0, r, cxk = g.frog ? 62 : g.ex + 10, cyk = g.frog ? 8 : g.ey + 19;
      for (d = 18; d <= 162; d += 8, j++) { r = g.rAt(d * DEG) * R - 15 + (j % 2 ? -4 : 4); lo.push([r * Math.cos(d * DEG), r * Math.sin(d * DEG)]); }
      for (d = -162, j = 0; d <= -18; d += 8, j++) { r = g.rAt(d * DEG) * R - 15 + (j % 2 ? -4 : 4); hi.push([r * Math.cos(d * DEG), r * Math.sin(d * DEG)]); }
      return [
        F(full(), GINGER, 1, true),
        S(new Path().smooth(lo, false), WHITE, 5.5, 1, true),
        S(new Path().smooth(hi, false), WHITE, 5.5, 1, true),
        F(new Path().ell(-cxk, cyk, 11, 7).ell(cxk, cyk, 11, 7), PINK, 0.6, true),
        S(new Path().dot(0, g.fy + 34), RED, 13, 1, true),
        S(new Path().dot(0, g.fy + 52), GREEN, 13, 1, true)
      ];
    },
    giftWrap: function (g) {
      var dots = new Path(), y, x, row = 0;
      for (y = -130; y <= 110; y += 40, row++) for (x = -140 + (row % 2 ? 20 : 0); x <= 140; x += 40) dots.dot(x, y);
      return [
        S(dots, GOLD, 12, 1, true),
        F(new Path().rect(-11, -260, 22, 520), RED, 1, true),
        F(new Path().rect(-200, g.fy + 34, 400, 18), RED, 1, true),
        F(new Path().rect(-11, g.fy + 34, 22, 18), RED_D, 1, true)
      ];
    },
    frost: function (g) {
      var yb = g.botY - 26, p = new Path().M(-170, 260).L(-170, yb), j, x, cr = new Path();
      for (j = 0, x = -170; j < 10; j++, x += 34) p.Q(x + 17, yb - (j % 2 ? 16 : 8), x + 34, yb);
      p.L(170, 260).Z();
      [[-64, -36], [60, -46], [-28, 50], [66, 36], [6, -70]].forEach(function (q) { cr.flake(q[0], q[1], 9, false); });
      return [F(full(), '#BFE3FF', 0.55, true), F(p, WHITE, 0.92, true), S(cr, WHITE, 3, 1, true)];
    },
    // A row of pines standing in snow along the bottom of the body, kept
    // below the eyes. The pill colour stays as the sky.
    snowyPines: function (g) {
      var base = g.botY - 16, hmax = Math.min(52, base - (g.fy + 20));
      var back = new Path(), front = new Path(), caps = new Path();
      function tree(p, x, h, w, cap) {
        for (var k = 0; k < 3; k++) {
          var top = base - h + k * h * 0.27, bot = top + h * 0.46, hw = w * (0.5 + 0.25 * k);
          p.poly([[x, top], [x + hw, bot], [x - hw, bot]]);
          if (cap && k === 0) caps.poly([[x, top], [x + hw * 0.5, top + h * 0.23], [x - hw * 0.5, top + h * 0.23]]);
        }
      }
      [-69, -23, 23, 69].forEach(function (x, i) { var h = hmax * (i % 2 ? 0.62 : 0.54); tree(back, x, h, h * 0.36, false); });
      [[-92, 0.82], [-46, 1], [0, 0.72], [46, 1], [92, 0.82]].forEach(function (q) { var h = hmax * q[1]; tree(front, q[0], h, h * 0.36, true); });
      function ground(m) {
        var p = new Path(m).M(-170, 260).L(-170, base - 4), j, x;
        for (j = 0, x = -170; j < 5; j++, x += 68) p.Q(x + 34, base - 4 - (j % 2 ? 10 : 4), x + 68, base - 4);
        return p.L(170, 260).Z();
      }
      return [F(back, GREEN, 1, true), F(front, GREEN_D, 1, true), F(caps, WHITE, 0.95, true),
        F(ground(mat(0, -3, 0, 1, 1)), SHADE, 1, true), F(ground(null), WHITE, 1, true)];
    }
  };

  // ── Extra ────────────────────────────────────────────────────────────────

  function sag(y0, depth, half, slope, step) {
    var pts = [], x;
    for (x = -half; x <= half + 0.01; x += step) pts.push([x, y0 + depth * (1 - Math.pow(x / half, 2)) + (slope || 0) * x]);
    return pts;
  }

  var EXTRA = {
    beard: function (g) {
      // The beard hangs from just under the eyes. The frog's eyes are on top
      // of its head, so its beard starts higher and comes further up the sides.
      var pts = [], t, r, fy = g.frog ? -58 : g.ey, t0 = g.frog ? -12 : 12, a = [];
      for (t = t0; t <= 180 - t0; t += 6) {
        r = g.rAt(t * DEG) * R + 6 + 8 * Math.abs(Math.sin((t - t0) / (180 - 2 * t0) * PI * 6));
        pts.push([r * Math.cos(t * DEG), r * Math.sin(t * DEG)]);
      }
      var p0 = pts[0], p1 = pts[pts.length - 1];
      var bd = new Path().smooth(pts, false).C(p1[0] + 40, fy + 52, p0[0] - 40, fy + 52, p0[0], p0[1]).Z();
      a.push(F(bd, WHITE)); a.push(S(bd, SHADE, 2.5));
      [1, -1].forEach(function (sd) {
        var m = mat(sd * 20, fy + 40, sd * 0.32, 1, 1), mo = new Path(m).ell(0, 0, 21, 10);
        a.push(F(mo, WHITE)); a.push(S(mo, SHADE, 2));
      });
      a.push(F(new Path().ell(0, fy + 29, 7.5, 7.5), PINK));
      return { a: a, z: [] };
    },
    lights: function (g) {
      var sw = g.frog
        ? [{ y: -28, d: 10, s: 0.04, xs: [-96, -48, 0, 48, 96] }, { y: 28, d: 14, s: -0.06, xs: [-72, -24, 24, 72] }]
        : [{ y: g.fy - 46, d: 12, s: 0.04, xs: [-96, -48, 0, 48, 96] }, { y: g.fy + 30, d: 16, s: -0.06, xs: [-72, -24, 24, 72] }];
      var cols = ['#FF4D6D', YELLOW, '#34D399', BLUE], bulbs = [new Path(), new Path(), new Path(), new Path()];
      var wire = new Path(), caps = new Path(), n = 0, a = [];
      sw.forEach(function (q) {
        wire.smooth(sag(q.y, q.d, 135, q.s, 15), false);
        q.xs.forEach(function (x) {
          var y = q.y + q.d * (1 - Math.pow(x / 135, 2)) + q.s * x;
          caps.dot(x, y + 2); bulbs[n % 4].dot(x, y + 10); n++;
        });
      });
      a.push(S(wire, '#1B3B2E', 3, 1, true));
      bulbs.forEach(function (b, i) { a.push(S(b, cols[i], 28, 0.25, true, i % 2 ? 'mn-glow-b' : 'mn-glow-a')); });
      a.push(S(caps, '#1B3B2E', 7, 1, true));
      bulbs.forEach(function (b, i) { a.push(S(b, cols[i], 15, 1, true, i % 2 ? 'mn-bulb-b' : 'mn-bulb-a')); });
      return { a: a, z: [] };
    },
    scarf: function (g) {
      var fy = g.fy, band = sag(fy + 40, 10, 150, 0, 30), a = [], fr = new Path(), x;
      a.push(S(new Path().smooth(band, false), RED, 24, 1, true));
      a.push(S(new Path(mat(0, -6, 0, 1, 1)).smooth(band, false), WHITE, 3.5, 0.9, true));
      a.push(S(new Path(mat(0, 6, 0, 1, 1)).smooth(band, false), WHITE, 3.5, 0.9, true));
      a.push(F(new Path().poly([[-62, fy + 56], [-38, fy + 58], [-34, fy + 100], [-60, fy + 102]]), RED));
      a.push(S(new Path().M(-59, fy + 82).L(-36, fy + 81).M(-59, fy + 91).L(-35, fy + 90), WHITE, 3.5, 0.9));
      for (x = -57; x <= -37; x += 6.6) fr.M(x, fy + 102).L(x, fy + 109);
      a.push(S(fr, RED_D, 3));
      a.push(F(new Path().rr(-66, fy + 34, 26, 30, 9), RED_D));
      return { a: a, z: [] };
    },
    snowfall: function () {
      var big = new Path(), small = new Path(), fl = new Path();
      [[-150, -168], [128, -158], [150, 22], [-120, 118], [176, 96]].forEach(function (q) { big.dot(q[0] * 0.88, q[1] * 0.78); });
      [[-96, -204], [58, -212], [166, -82], [-170, -58], [-160, 62], [100, 128], [-20, -200], [20, 134]].forEach(function (q) { small.dot(q[0] * 0.88, q[1] * 0.78); });
      fl.flake(-121, -90, 12, true).flake(125, -27, 10, true);
      return { a: [], z: [S(big, WHITE, 13, 0.95), S(small, WHITE, 9, 0.9), S(fl, WHITE, 2.6, 0.95)] };
    },
    redNose: function (g) {
      var y = g.ny;
      return { a: [S(new Path().dot(0, y), '#FF4D6D', 46, 0.28), F(new Path().ell(0, y, 13, 13), RED),
        F(new Path().ell(-4.5, y - 4.5, 3, 4), WHITE, 0.9)], z: [] };
    },
    wreath: function (g) {
      var fy = g.fy, d1 = new Path(), d2 = new Path(), be = new Path(), x;
      function yy(v) { return fy + 44 + 8 * (1 - Math.pow(v / 120, 2)); }
      for (x = -120; x <= 120; x += 24) d1.dot(x, yy(x));
      for (x = -108; x <= 108; x += 24) d2.dot(x, yy(x) - 4);
      [-84, -36, 36, 84].forEach(function (v) { be.dot(v, yy(v) + 2); });
      return { a: [S(d1, GREEN_D, 26, 1, true), S(d2, GREEN, 15, 1, true), S(be, RED, 8, 1, true),
        F(new Path().poly([[0, fy + 54], [-17, fy + 44], [-17, fy + 64]]).poly([[0, fy + 54], [17, fy + 44], [17, fy + 64]]), RED),
        S(new Path().dot(0, fy + 54), RED_D, 9)], z: [] };
    },
    bell: function (g) {
      var fy = g.fy, m = mat(0, fy + 60, 0, 1, 1);
      return { a: [
        S(new Path().smooth(sag(fy + 40, 8, 150, 0, 30), false), RED, 7, 1, true),
        S(new Path(m).dot(0, -17), GOLD_D, 6),
        F(new Path(m).M(-13, 10).C(-13, -8, -8, -16, 0, -16).C(8, -16, 13, -8, 13, 10).L(17, 14).L(-17, 14).Z(), GOLD),
        S(new Path(m).dot(0, 17), GOLD_D, 8),
        F(new Path(m).ell(-5, -3, 2.5, 6), GOLD_L)
      ], z: [] };
    },
    carrot: function (g) {
      var c = g.ny + 2;
      return { a: [
        F(new Path().ell(-2, c, 9, 9).poly([[-2, c - 9], [48, c + 3], [-2, c + 9]]), '#FF8A2B'),
        S(new Path().M(10, c - 4).L(10, c + 1).M(22, c - 1).L(22, c + 3), '#D96A12', 2.2)
      ], z: [] };
    }
  };

  function parts(body) {
    var g = geo(body), out = { eye: { x: g.ex, y: g.ey, s: g.eyeS }, heads: {}, eyes: {}, textures: {}, extras: {} };
    var bp = new Path().smooth(g.pts, true);
    g.sock.forEach(function (k) { bp.ell(k.x * R, k.y * R, k.r * R, k.r * R); });
    out.clip = bp.d();
    out.hatY = g.hatY();
    Object.keys(HEAD).forEach(function (id) { var h = HEAD[id](g, '@skin'); out.heads[id] = { b: h.b, f: h.f }; });
    EYE_IDS.forEach(function (id) { out.eyes[id] = eyes(id, g, false); });
    Object.keys(TEX).forEach(function (id) { out.textures[id] = TEX[id](g); });
    Object.keys(EXTRA).forEach(function (id) { var e = EXTRA[id](g); out.extras[id] = { a: e.a, z: e.z }; });
    return out;
  }
  var EYE_IDS = ['starEye', 'snowflake', 'coal', 'bauble', 'peppermint', 'bulb', 'jolly', 'treeGlasses', 'wreathGlasses'];

  return { parts: parts };
}

// ---------------------------------------------------------------------------
// Out.

const ANIM = { 'mn-bulb-a': 'bulbA', 'mn-bulb-b': 'bulbB', 'mn-glow-a': 'glowA', 'mn-glow-b': 'glowB', 'mn-lit': 'lit', 'mn-shine-a': 'shineA', 'mn-shine-b': 'shineB' };
const r2 = (n) => Math.round(n * 100) / 100;
function prim(p) {
  const o = { d: p.d };
  if (p.f !== 'none') o.f = p.f;
  if (p.s !== 'none') { o.s = p.s; o.w = r2(p.w); }
  if (p.o !== 1) o.o = r2(p.o);
  if (p.c) o.c = 1;
  if (p.k) { if (!ANIM[p.k]) throw new Error('unknown animation ' + p.k); o.k = ANIM[p.k]; }
  return o;
}
const prims = (list) => list.map(prim);

// The engines draw a Mochi in a canvas where the body is 60 % of the width:
// about 167 units of room each side of the centre and 173 above it. A head
// part that reaches past that would be sliced flat at the canvas edge, so it
// is scaled down about the top of the head until it fits — the tall hats come
// out a little smaller on a low head than on a pointed one, never cut. The side
// allowance is tighter than the canvas: a head part leans up to 16 units with
// the head as it turns, and an ear tip should still be there mid-turn.
const ROOM = { side: 150, top: -170 };
const PAIR = /(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g;
function fit(lists, pivotY) {
  let far = 0, top = 0;
  for (const list of lists) for (const p of list) {
    const half = p.s !== 'none' ? p.w / 2 : 0;
    for (const m of p.d.matchAll(PAIR)) { far = Math.max(far, Math.abs(+m[1]) + half); top = Math.min(top, +m[2] - half); }
  }
  const k = Math.min(1, far > ROOM.side ? ROOM.side / far : 1, top < ROOM.top ? (pivotY - ROOM.top) / (pivotY - top) : 1);
  if (k >= 1) return lists;
  const f1 = (n) => String(Math.round(n * 10) / 10);
  return lists.map((list) => list.map((p) => ({ ...p, w: p.w * k, d: p.d.replace(PAIR, (_, x, y) => f1(+x * k) + ' ' + f1(pivotY + (+y - pivotY) * k)) })));
}

const kit = makeKit(SH);
const data = { version: 1, catalog: CATALOG, bodies: {} };
for (const body of ['classic', 'round', 'boxy', 'fluffy', 'pointy', 'heart', 'frog', 'ato']) {
  const p = kit.parts(body), out = { eye: { x: r2(p.eye.x), y: r2(p.eye.y), s: r2(p.eye.s) }, clip: p.clip, heads: {}, eyes: {}, textures: {}, extras: {} };
  for (const [id] of CATALOG.heads) { const [b, f] = fit([p.heads[id].b, p.heads[id].f], p.hatY); out.heads[id] = { b: prims(b), f: prims(f) }; }
  for (const [id] of CATALOG.eyes) out.eyes[id] = { l: prims(p.eyes[id].l), r: prims(p.eyes[id].r), over: prims(p.eyes[id].over) };
  for (const [id] of CATALOG.textures) out.textures[id] = prims(p.textures[id]);
  for (const [id] of CATALOG.extras) out.extras[id] = { a: prims(p.extras[id].a), z: prims(p.extras[id].z) };
  data.bodies[body] = out;
}
const json = JSON.stringify(data);
if (/NaN|Infinity|undefined/.test(json)) throw new Error('a part came out with a bad number');
if (json.includes('"""#') || json.includes('`') || json.includes('\\')) throw new Error('the JSON would not survive being quoted');

const NOTE = 'Generated by scripts/generate-mochi-festive.mjs — do not edit by hand.';
const swift = `// ${NOTE}
//
// Everything a Mochi can wear at Christmas, worked out per body by the
// generator and decoded once by MochiFestive. The format is described at the
// top of the generator.

enum MochiFestiveData {
    static let json: String = #"""
${json}
"""#
}
`;
const ts = `// ${NOTE}
//
// Everything a Mochi can wear at Christmas, worked out per body by the
// generator. The format is described at the top of the generator.

export interface FestivePrim { d: string; f?: string; s?: string; w?: number; o?: number; c?: 1; k?: string }
export interface FestiveBody {
  eye: { x: number; y: number; s: number };
  clip: string;
  heads: Record<string, { b: FestivePrim[]; f: FestivePrim[] }>;
  eyes: Record<string, { l: FestivePrim[]; r: FestivePrim[]; over: FestivePrim[] }>;
  textures: Record<string, FestivePrim[]>;
  extras: Record<string, { a: FestivePrim[]; z: FestivePrim[] }>;
}
export interface FestivePresetRow { id: string; name: string; head: string | null; eyes: string | null; texture: string | null; extra: string | null }
export interface FestiveData {
  version: number;
  catalog: { heads: [string, string][]; eyes: [string, string][]; textures: [string, string][]; extras: [string, string][]; presets: FestivePresetRow[] };
  bodies: Record<string, FestiveBody>;
}

export const FESTIVE_JSON = '${json}';
`;
// Notchy for Android reads the same document as an asset (mochi/MochiFestive.kt), parsed on first use.
const android = json + '\n';
const targets = [
  ['NotchBuddy/Sources/App/MochiFestiveData.swift', swift],
  ['windows/src/mochi/festive.generated.ts', ts],
  ['android/app/src/main/assets/festive.json', android],
];
if (process.argv.includes('--write')) {
  for (const [path, text] of targets) writeFileSync(path, text);
  console.log(`wrote ${targets.length} files, ${(json.length / 1024).toFixed(0)} KB of parts`);
} else {
  let stale = 0;
  for (const [path, text] of targets) {
    let have = '';
    try { have = readFileSync(path, 'utf8'); } catch { /* missing counts as stale */ }
    if (have !== text) { stale++; console.error(`${path} is stale: run node scripts/generate-mochi-festive.mjs --write`); }
  }
  process.exit(stale ? 1 : 0);
}
