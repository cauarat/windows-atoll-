#!/usr/bin/env node
// Turns the six reference bodies into the tables Mochi is drawn from.
//
// Run it with `node scripts/generate-mochi-shapes.mjs --write` and it rewrites
// the generated block in both MochiShape.swift and windows/src/mochi/shape.ts.
// Both sides come out of this one file so they cannot drift: the parity test
// compares them, but this is what makes them equal in the first place.
//
// Why tables and not SVG paths parsed at runtime: flattening cubics and
// converting endpoint arcs to centres is about 160 lines that would have to
// agree bit-for-bit between Swift and TypeScript. Generating literals moves
// that agreement from runtime to build time, where it can be checked once.
//
// The shape of the output, per body:
//   r[]      radii at N evenly spaced angles about the body's own centre.
//            A radial table is the right form because the engine already
//            thinks this way — the mailbox morph lerps sample i toward the
//            rounded rect at sample i's angle, so a table drops straight in.
//   sockets  circles drawn as part of the silhouette, with a pupil moving
//            inside each. Only the frog has them, and they are why it can keep
//            a radial body table despite not being star-shaped as a whole.

// ---------------------------------------------------------------------------
// The reference bodies, in their original 200x200 viewBox.

const BODIES = {
  round:  'M12 262 L12 152 C12 98 52 72 100 72 C148 72 188 98 188 152 L188 262 Z',
  boxy:   'M14 262 L14 104 C14 72 36 52 68 52 L132 52 C164 52 186 72 186 104 L186 262 Z',
  fluffy: 'M16 262 C2 240 0 206 16 190 C0 170 6 138 34 134 C30 108 56 92 82 100 '
        + 'C94 82 132 80 146 100 C172 96 196 118 186 146 C204 160 202 196 186 208 '
        + 'C196 226 192 250 186 262 Z',
  pointy: 'M12 262 L14 180 C18 120 60 36 100 34 C140 36 182 120 186 180 L188 262 Z',
  heart:  'M100 290 C58 254 8 204 8 132 C8 86 38 56 70 56 C86 56 96 64 100 78 '
        + 'C104 64 114 56 130 56 C162 56 192 86 192 132 C192 204 142 254 100 290 Z',
  frog:   'M16 262 L16 176 C16 132 52 112 100 112 C148 112 184 132 184 176 L184 262 Z',
};

// Where the face and the hats go, straight from the reference's own metadata:
// `top` is the crown of the head, `ears` the two attach points for cat ears and
// horns, `eyes` the eye row as [y, spread], `cheek` the blush offset.
const FACE = {
  round:  { top: 72, ears: [[46, 98], [154, 98]],  eyes: [140, 23], cheek: 42 },
  boxy:   { top: 52, ears: [[38, 66], [162, 66]],  eyes: [124, 26], cheek: 46 },
  fluffy: { top: 86, ears: [[50, 108], [158, 106]], eyes: [158, 17], cheek: 34 },
  pointy: { top: 34, ears: [[70, 70], [130, 70]],  eyes: [136, 25], cheek: 38 },
  heart:  { top: 70, ears: [[52, 66], [148, 66]],  eyes: [134, 25], cheek: 40 },
  frog:   { top: 64, ears: [[40, 80], [160, 80]],  eyes: [98, 36],  cheek: 52 },
};

// Classic Mochi's own face, for the shapes to be measured against.
const CLASSIC_FACE = { eyeW: 0.25, eyeH: 0.27, eyeSp: 0.37, eyeP: -0.12 };

// The frog's eye bulges. Part of the silhouette, and also where its pupils live.
//
// The reference circles sit at x=64 and x=136 with r=36, which makes them
// exactly tangent at (100,100). A zero-width cusp renders as a flickering crack
// in the frog's forehead once the body starts squashing under it, so they are
// nudged 4 units inward to overlap instead of touch. A deliberate departure from
// the reference data, and the only one.
const SOCKETS = { frog: [{ x: 68, y: 100, r: 36 }, { x: 132, y: 100, r: 36 }] };

// The reference pals sit on an edge, so everything below the viewBox is just
// off-screen filler — straight walls holding the body up. Mochi floats, so that
// filler has to become a real bottom.
//
// Where the filler starts differs per shape, and one rule does not fit: round's
// dome ends at y=144 and is a straight wall below it, while fluffy's lower lobes
// are genuinely drawn and heart is already closed at its point. `cut` is where
// the design ends; `belly` is how far the invented base bulges below it, as a
// fraction of the half-width there. A null cut means the shape keeps its own
// bottom — cutting the heart makes its base poke through the narrowing flank and
// costs it star-shapedness.
const BOTTOM = {
  round:  { cut: 160,  belly: 0.62 },
  boxy:   { cut: 150,  belly: 0.55 },
  fluffy: { cut: 212,  belly: 0.18 },
  pointy: { cut: 150,  belly: 0.52 },
  // The heart is the one shape whose reference path is already closed, at a
  // valentine point down at y=290. Keeping it would be faithful to the data and
  // wrong for the art: the point is below the viewBox, so it never appears in
  // the reference, where this shape reads as an apple. Cut it to the apple.
  heart:  { cut: 228,  belly: 0.45 },
  frog:   { cut: 190,  belly: 0.50 },
};

// How far to pull each shape's aspect toward Mochi's own 1.295, area-preserving.
// Equal area alone leaves pointy and heart noticeably lankier than the family;
// at 0.45 nothing moves more than ~15% and every shape stays itself.
const ASPECT_PULL = 0.45;
const CLASSIC_ASPECT = 1.295;
const RY_MAX = 1.02;     // heart would otherwise stand 25% taller than classic

// Classic Mochi, for reference and for area-matching: a superellipse of
// exponent 2.7 with rx = 1.14R, ry = 0.88R.
const CLASSIC = { rx: 1.14, ry: 0.88, exp: 2.0 / 2.7 };

const LODS = [72, 36, 24];
const NL = String.fromCharCode(10);

// ---------------------------------------------------------------------------
// Path flattening.

function flatten(d, steps = 48) {
  const t = d.match(/[MLCQAZmlcqaz]|-?[\d.]+/g);
  let i = 0, subs = [], cur = null, x = 0, y = 0, sx = 0, sy = 0, cmd = null;
  const num = () => parseFloat(t[i++]);
  while (i < t.length) {
    if (/[MLCQAZmlcqaz]/.test(t[i])) cmd = t[i++];
    if (cmd === 'M') { x = num(); y = num(); cur = [[x, y]]; subs.push(cur); sx = x; sy = y; cmd = 'L'; }
    else if (cmd === 'L') { x = num(); y = num(); cur.push([x, y]); }
    else if (cmd === 'C') {
      const a = num(), b = num(), c = num(), e = num(), f = num(), g = num();
      for (let k = 1; k <= steps; k++) {
        const u = k / steps, v = 1 - u;
        cur.push([v*v*v*x + 3*v*v*u*a + 3*v*u*u*c + u*u*u*f,
                  v*v*v*y + 3*v*v*u*b + 3*v*u*u*e + u*u*u*g]);
      }
      x = f; y = g;
    } else if (cmd === 'Q') {
      const a = num(), b = num(), c = num(), e = num();
      for (let k = 1; k <= steps; k++) {
        const u = k / steps, v = 1 - u;
        cur.push([v*v*x + 2*v*u*a + u*u*c, v*v*y + 2*v*u*b + u*u*e]);
      }
      x = c; y = e;
    } else if (cmd === 'Z' || cmd === 'z') { x = sx; y = sy; cmd = null; }
    else i++;
  }
  return subs;
}

// ---------------------------------------------------------------------------
// Geometry helpers.

const area = (p) => { let a = 0; for (let i = 0, n = p.length; i < n; i++) { const [x1,y1]=p[i], [x2,y2]=p[(i+1)%n]; a += x1*y2 - x2*y1; } return Math.abs(a/2); };

/** Clip a polygon to y <= yMax (Sutherland–Hodgman against one half-plane). */
function clipBelow(poly, yMax) {
  const out = [];
  for (let i = 0, n = poly.length; i < n; i++) {
    const a = poly[i], b = poly[(i + 1) % n];
    const ain = a[1] <= yMax, bin = b[1] <= yMax;
    if (ain) out.push(a);
    if (ain !== bin) {
      const t = (yMax - a[1]) / (b[1] - a[1]);
      out.push([a[0] + (b[0] - a[0]) * t, yMax]);
    }
  }
  return out;
}

/** Replace the flat cut along y=yMax with a bulge, so the body has a bottom.
 *
 *  `clipBelow` leaves exactly one edge lying on the cut; this swaps that edge
 *  for a half-superellipse. Editing the clipped polygon in place keeps the
 *  winding order, which rebuilding it from a filtered vertex list does not.
 */
function capBase(poly, yMax, depthFrac) {
  const onCut = (p) => Math.abs(p[1] - yMax) < 1e-7;
  let at = -1;
  for (let i = 0; i < poly.length; i++) {
    if (onCut(poly[i]) && onCut(poly[(i + 1) % poly.length])) { at = i; break; }
  }
  if (at < 0) return poly;

  const a = poly[at], b = poly[(at + 1) % poly.length];
  const half = Math.abs(b[0] - a[0]) / 2, cx = (a[0] + b[0]) / 2;
  const depth = half * depthFrac;
  const dir = Math.sign(b[0] - a[0]) || 1;

  // Exponent 2.4: fuller than an ellipse, so the base reads as a body settling
  // rather than a balloon.
  const STEPS = 64, EXP = 2.0 / 2.4, arc = [];
  for (let k = 1; k < STEPS; k++) {
    const t = Math.PI * (k / STEPS);
    const c = Math.cos(t), sn = Math.sin(t);
    arc.push([cx - dir * half * (c >= 0 ? Math.pow(c, EXP) : -Math.pow(-c, EXP)),
              yMax + depth * Math.pow(sn, EXP)]);
  }
  return poly.slice(0, at + 1).concat(arc, poly.slice(at + 1));
}

/** Does a ray from c leave the polygon exactly once in every direction? */
function starShaped(poly, c, rays = 720) {
  const inside = (px, py) => {
    let w = 0;
    for (let i = 0, n = poly.length; i < n; i++) {
      const [x1,y1] = poly[i], [x2,y2] = poly[(i+1)%n];
      if (y1 <= py) { if (y2 > py && ((x2-x1)*(py-y1)-(px-x1)*(y2-y1)) > 0) w++; }
      else { if (y2 <= py && ((x2-x1)*(py-y1)-(px-x1)*(y2-y1)) < 0) w--; }
    }
    return w !== 0;
  };
  const R = 2 * Math.max(...poly.map(p => Math.hypot(p[0]-c[0], p[1]-c[1])));
  let worst = 0;
  for (let k = 0; k < rays; k++) {
    const th = k / rays * 2 * Math.PI, dx = Math.cos(th), dy = Math.sin(th);
    let flips = 0, prev = true;
    for (let r = R/400; r < R; r += R/400) {
      const ins = inside(c[0] + r*dx, c[1] + r*dy);
      if (ins !== prev) { flips++; prev = ins; }
    }
    worst = Math.max(worst, flips);
  }
  return worst <= 1;
}

/** Distance from c to the boundary along angle th. */
function rayHit(poly, c, th) {
  const dx = Math.cos(th), dy = Math.sin(th);
  let best = null;
  for (let i = 0, n = poly.length; i < n; i++) {
    const [x1,y1] = poly[i], [x2,y2] = poly[(i+1)%n];
    const ex = x2-x1, ey = y2-y1;
    const den = dx*ey - dy*ex;
    if (Math.abs(den) < 1e-12) continue;
    const t = ((x1-c[0])*ey - (y1-c[1])*ex) / den;     // along the ray
    const u = ((x1-c[0])*dy - (y1-c[1])*dx) / den;     // along the edge
    if (t >= 0 && u >= -1e-9 && u <= 1+1e-9) best = best === null ? t : Math.max(best, t);
  }
  return best ?? 0;
}

const centroidOf = (poly) => {
  let a = 0, cx = 0, cy = 0;
  for (let i = 0, n = poly.length; i < n; i++) {
    const [x1,y1] = poly[i], [x2,y2] = poly[(i+1)%n];
    const f = x1*y2 - x2*y1; a += f; cx += (x1+x2)*f; cy += (y1+y2)*f;
  }
  a /= 2; return [cx/(6*a), cy/(6*a)];
};

// ---------------------------------------------------------------------------
// Classic Mochi's area, which every shape is matched to.

function classicArea() {
  const N = 4000; let a = 0;
  const pt = (t) => { const c = Math.cos(t), s = Math.sin(t);
    return [CLASSIC.rx * (c >= 0 ? Math.pow(c, CLASSIC.exp) : -Math.pow(-c, CLASSIC.exp)),
            CLASSIC.ry * (s >= 0 ? Math.pow(s, CLASSIC.exp) : -Math.pow(-s, CLASSIC.exp))]; };
  for (let i = 0; i < N; i++) {
    const [x1,y1] = pt(i/N*2*Math.PI), [x2,y2] = pt((i+1)/N*2*Math.PI);
    a += x1*y2 - x2*y1;
  }
  return Math.abs(a/2);
}

/** Union area of body + sockets, by rasterising. Only the frog needs it. */
function unionArea(poly, sockets, step = 0.35) {
  const xs = poly.map(p=>p[0]), ys = poly.map(p=>p[1]);
  let x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  for (const s of sockets) { x0 = Math.min(x0, s.x-s.r); x1 = Math.max(x1, s.x+s.r); y0 = Math.min(y0, s.y-s.r); y1 = Math.max(y1, s.y+s.r); }
  const inside = (px, py) => {
    for (const s of sockets) if (Math.hypot(px-s.x, py-s.y) <= s.r) return true;
    let w = 0;
    for (let i = 0, n = poly.length; i < n; i++) {
      const [ax,ay] = poly[i], [bx,by] = poly[(i+1)%n];
      if (ay <= py) { if (by > py && ((bx-ax)*(py-ay)-(px-ax)*(by-ay)) > 0) w++; }
      else { if (by <= py && ((bx-ax)*(py-ay)-(px-ax)*(by-ay)) < 0) w--; }
    }
    return w !== 0;
  };
  let n = 0;
  for (let y = y0; y <= y1; y += step) for (let x = x0; x <= x1; x += step) if (inside(x,y)) n++;
  return n * step * step;
}

// ---------------------------------------------------------------------------
// Build.

const CA = classicArea();
const shapes = {};

/** Half-extents of a radial table, in R units. */
function extents(r) {
  const N = r.length;
  let rx = 0, top = 0, bot = 0;
  for (let i = 0; i < N; i++) {
    const t = i / N * 2 * Math.PI;
    rx = Math.max(rx, Math.abs(r[i] * Math.cos(t)));
    top = Math.min(top, r[i] * Math.sin(t));
    bot = Math.max(bot, r[i] * Math.sin(t));
  }
  return { rx, top, bot, ry: (bot - top) / 2 };
}

for (const [name, d] of Object.entries(BODIES)) {
  const bottom = BOTTOM[name];
  let poly = flatten(d)[0];
  if (bottom.cut !== null) {
    poly = clipBelow(poly, bottom.cut);
    poly = capBase(poly, bottom.cut, bottom.belly);
  }

  const sockets = (SOCKETS[name] ?? []).map((k) => ({ ...k }));
  const rawArea = sockets.length ? unionArea(poly, sockets) : area(poly);

  // Centre on the area centroid of the whole creature: it is what balances the
  // body visually, and it is also the origin the squash and tilt pivots and
  // every accessory anchor are measured from.
  let c = centroidOf(poly);
  if (sockets.length) {
    const extra = rawArea - area(poly);
    const sc = sockets.reduce((a, k) => [a[0] + k.x, a[1] + k.y], [0, 0]).map((v) => v / sockets.length);
    const w = extra / rawArea;
    c = [c[0] * (1 - w) + sc[0] * w, c[1] * (1 - w) + sc[1] * w];
  }

  if (!starShaped(poly, c)) {
    console.error(`!! ${name}: body is not star-shaped about its centre — a radial table would distort it.`);
    process.exitCode = 1;
  }

  // Equal area with classic Mochi, so no shape looks heavier than another in
  // the same pill, then the aspect pulled partway toward Mochi's own.
  const uniform = Math.sqrt(CA / rawArea);
  const probe = extents(Array.from({ length: 144 }, (_, i) => rayHit(poly, c, i / 144 * 2 * Math.PI) * uniform));
  const aspect = probe.rx / probe.ry;
  const want = aspect + (CLASSIC_ASPECT - aspect) * ASPECT_PULL;
  let kx = Math.sqrt(want / aspect), ky = 1 / kx;
  if (probe.ry * ky > RY_MAX) { ky = RY_MAX / probe.ry; kx = 1 / ky; }

  const tables = {};
  for (const N of LODS) {
    tables[N] = Array.from({ length: N }, (_, i) => {
      const t = i / N * 2 * Math.PI;
      const r = rayHit(poly, c, t) * uniform;
      // Anisotropic scale on a radial table: re-measure the radius after it.
      return Math.hypot(r * Math.cos(t) * kx, r * Math.sin(t) * ky);
    });
  }

  const ext = extents(tables[72]);
  const nx = (px) => (px - c[0]) * uniform * kx;
  const ny = (py) => (py - c[1]) * uniform * ky;

  // The engine hangs everything worn on a sphere of (rxK, ryK) at an azimuth
  // and an elevation, so the reference's flat 2-D attach points have to become
  // angles. asin inverts the projection; the clamp only ever bites on a point
  // the reference put fractionally outside its own bounding box.
  const clamp1 = (v) => Math.max(-0.999, Math.min(0.999, v));
  const f = FACE[name];
  const [eyeY, spread] = f.eyes;

  // Breathing is a constant travel, not a constant ratio: a tall pal at
  // classic's 0.035 would heave twice as far as a wide one. Classic's crown
  // moves 0.035 * 0.88 R, so each shape scales to cover the same distance.
  const CLASSIC_CROWN_TRAVEL = 0.035 * 0.88;
  const squashAnchorY = ext.bot * 0.72;      // compress toward the base, not the middle
  const breathScale = CLASSIC_CROWN_TRAVEL / (0.035 * (squashAnchorY - ext.top));

  shapes[name] = {
    r: tables,
    sockets: sockets.map((k) => ({
      x: nx(k.x), y: ny(k.y), r: k.r * uniform * (kx + ky) / 2,
    })),
    a: {
      rxK: ext.rx, ryK: ext.ry, top: ext.top, bottom: ext.bot,
      eyeW: CLASSIC_FACE.eyeW, eyeH: CLASSIC_FACE.eyeH,
      eyeSp: Math.asin(clamp1(nx(100 + spread) / ext.rx)),
      eyeP: -Math.asin(clamp1(ny(eyeY) / ext.ry)),
      earA0: Math.asin(clamp1(nx(f.ears[1][0]) / ext.rx)),
      earE0: Math.asin(clamp1(-ny(f.ears[1][1]) / ext.ry)),
      crownE0: Math.asin(clamp1(-ny(f.top) / ext.ry)),
      cheekK: nx(100 + f.cheek) / ext.rx,
      // Hands ride the real outline, not the bounding box: on pointy the body
      // is well inside rxK down at hand height, and a hand pinned to rxK would
      // float free of the body.
      handX: rayHit(poly, c, 0) * uniform * kx * 0,   // replaced below
      pivotY: ext.bot,
      squashAnchorY,
      breathScale,
      // How much bigger this body's eyes are than the usual ones.
      //
      // Only a socketed body needs it: a pupil has to fill its eyeball, and at
      // the standard 0.25 R the frog looked like it had two pinpricks rattling
      // around in a pair of goggles. Everything else keeps the eyes its chosen
      // kind comes with.
      eyeScale: sockets.length
        ? (sockets[0].r * uniform * (kx + ky) / 2) * 2 * 0.43 / CLASSIC_FACE.eyeW
        : 1,
    },
  };

  // Where things are worn has to follow the real head, not a bounding ellipse.
  // The frog is the proof: its body table tops out at 0.52 R while its bulges
  // reach 1.11, so a crown placed on the body's ellipsoid would sit buried
  // inside them. This is a radius-per-direction of the whole creature, sockets
  // included, smoothed so a beret glides over pointy's apex and boxy's corners
  // instead of catching on them.
  {
    const RAW = 96, SMOOTH = 7;
    const union = [];
    for (let i = 0; i < RAW; i++) {
      const t = i / RAW * 2 * Math.PI, dx = Math.cos(t), dy = Math.sin(t);
      let r = rayHit(poly, c, t) * uniform;
      let bx = r * dx * kx, by = r * dy * ky;
      let best = Math.hypot(bx, by);
      for (const k of shapes[name].sockets) {
        // Farthest intersection of the ray with this socket, if it meets it.
        const b = k.x * dx + k.y * dy, cc = k.x * k.x + k.y * k.y - k.r * k.r;
        const disc = b * b - cc;
        if (disc > 0) best = Math.max(best, b + Math.sqrt(disc));
      }
      union.push(best);
    }
    const sm = union.map((_, i) => {
      let acc = 0;
      for (let j = -(SMOOTH >> 1); j <= (SMOOTH >> 1); j++) acc += union[(i + j + RAW) % RAW];
      return acc / SMOOTH;
    });
    shapes[name].anchor = Array.from({ length: 24 }, (_, i) => sm[Math.round(i * RAW / 24) % RAW]);
  }

  // Hand and badge anchors, measured off the silhouette itself.
  {
    const a = shapes[name].a;
    const atY = (yFrac) => {
      const y = a.ryK * yFrac;
      let best = 0;
      for (let i = 0; i < 720; i++) {
        const t = i / 720 * 2 * Math.PI;
        const r = rayHit(poly, c, t) * uniform;
        const px = r * Math.cos(t) * kx, py = r * Math.sin(t) * ky;
        if (Math.abs(py - y) < a.ryK * 0.06) best = Math.max(best, Math.abs(px));
      }
      return best || a.rxK;
    };
    a.handX = atY(0.70) * 1.08;
    a.handY = a.ryK * 0.70;
    a.badgeA0 = Math.asin(clamp1(-atY(-0.62) * 0.90 / a.rxK));
    a.badgeE0 = Math.asin(clamp1(0.62));
  }
}

// Classic Mochi, through the very same ray-cast as the rest.
//
// It has to be the same path. A superellipse's parameter t is not its polar
// angle once the exponent leaves 2 — sampling r at even t and storing it as if
// it were even theta dents the silhouette into a peanut. Flatten it, then cast
// rays at it like any other body.
{
  const DENSE = 4096;
  const poly = Array.from({ length: DENSE }, (_, i) => {
    const t = i / DENSE * 2 * Math.PI, ct = Math.cos(t), st = Math.sin(t);
    return [CLASSIC.rx * (ct >= 0 ? Math.pow(ct, CLASSIC.exp) : -Math.pow(-ct, CLASSIC.exp)),
            CLASSIC.ry * (st >= 0 ? Math.pow(st, CLASSIC.exp) : -Math.pow(-st, CLASSIC.exp))];
  });
  const tables = {};
  for (const N of LODS) {
    tables[N] = Array.from({ length: N }, (_, i) => rayHit(poly, [0, 0], i / N * 2 * Math.PI));
  }
  shapes.classic = { r: tables, sockets: [] };
}

// ---------------------------------------------------------------------------
// Report.

const order = ['classic', 'round', 'boxy', 'fluffy', 'pointy', 'heart', 'frog'];
console.log(`classic area = ${CA.toFixed(4)} R^2\n`);
console.log('shape    half-w  top     bottom  aspect  area    max step  sockets');
for (const name of order) {
  const s = shapes[name], r = s.r[72];
  let maxX = 0, top = 0, bot = 0;
  r.forEach((v, i) => { const t = i/72*2*Math.PI;
    maxX = Math.max(maxX, Math.abs(v*Math.cos(t)));
    top = Math.min(top, v*Math.sin(t)); bot = Math.max(bot, v*Math.sin(t)); });
  let a = 0; for (let i = 0; i < 72; i++) a += 0.5 * r[i] * r[(i+1)%72] * Math.sin(2*Math.PI/72);
  for (const k of s.sockets) a += Math.PI*k.r*k.r*0.42;   // rough, sockets overlap the body
  let step = 0; for (let i = 0; i < 72; i++) step = Math.max(step, Math.abs(r[i]-r[(i+1)%72])/r[i]);
  console.log(name.padEnd(9), maxX.toFixed(3).padEnd(8), top.toFixed(3).padEnd(8), bot.toFixed(3).padEnd(8),
    (maxX/((bot-top)/2)).toFixed(3).padEnd(8), a.toFixed(3).padEnd(8), step.toFixed(3).padEnd(10),
    s.sockets.length ? s.sockets.map(k=>`(${k.x.toFixed(2)},${k.y.toFixed(2)}) r${k.r.toFixed(2)}`).join(' ') : '-');
}

// ---------------------------------------------------------------------------
// A contact sheet, so the shapes can be judged against the reference art before
// any of this reaches the engine. `node scripts/generate-mochi-shapes.mjs --svg`

console.log(NL + 'shape    eyeSp   eyeP    earA0   earE0   crownE0  cheekK  handX   pivotY  breath');
for (const name of order.slice(1)) {
  const a = shapes[name].a;
  console.log(name.padEnd(9),
    a.eyeSp.toFixed(3).padEnd(8), a.eyeP.toFixed(3).padEnd(8),
    a.earA0.toFixed(3).padEnd(8), a.earE0.toFixed(3).padEnd(8),
    a.crownE0.toFixed(3).padEnd(9), a.cheekK.toFixed(3).padEnd(8),
    a.handX.toFixed(3).padEnd(8), a.pivotY.toFixed(3).padEnd(8),
    a.breathScale.toFixed(3));
}
console.log(`classic   ${CLASSIC_FACE.eyeSp.toFixed(3)}   ${CLASSIC_FACE.eyeP.toFixed(3)}   (reference)`);

// ---------------------------------------------------------------------------
// Emit.

const f6 = (v) => (Object.is(v, -0) ? 0 : v).toFixed(6);
const SHAPES = order.slice(1);                     // classic is not in the table
const LABEL = { round: 'Round', boxy: 'Boxy', fluffy: 'Fluffy',
                pointy: 'Pointy', heart: 'Heart', frog: 'Frog' };

const PREAMBLE = (what) => `// Generated by scripts/generate-mochi-shapes.mjs — do not edit by hand.
//
// ${what} for the six bodies a Mochi can have, measured off the reference art
// and normalised so no shape looks heavier than another in the same pill.
//
// Classic Mochi is deliberately absent. It is still drawn by the superellipse
// it always was, so picking no shape costs nothing and changes nothing — none
// of this is consulted unless somebody opens the picker.
//
// Radii are in units of R, at evenly spaced angles from +x, turning the way the
// canvas does. Three lengths of the same outline: 72 for the big bot, 36 and 24
// for the small ones, each sampled from the source rather than decimated, so a
// mini is a clean silhouette and not a dropped-vertex one.`;

// ---- Swift ----------------------------------------------------------------
const sw = [];
sw.push(PREAMBLE('The tables'));
sw.push('', 'import CoreGraphics', '');
sw.push(`/// What a Mochi is shaped like. \`nil\` is classic Mochi.
enum MochiShape: String, CaseIterable, Codable {
    case ${SHAPES.join(', ')}

    var label: String {
        switch self {
${SHAPES.map((n) => `        case .${n}:${' '.repeat(8 - n.length)} return "${LABEL[n]}"`).join('\n')}
        }
    }
}

/// A circle that is both part of the silhouette and a socket an eye sits in.
///
/// Only the frog has these, and they are what let it keep a plain radial body
/// table despite a silhouette that is not star-shaped: the bulges are drawn as
/// their own subpaths, and the eye inside one moves like a pupil in an eyeball
/// rather than like a point on a sphere.
struct MochiSocket: Equatable {
    let x, y, r: CGFloat
}

/// Everything the engine needs to draw a body that is not classic Mochi.
struct MochiShapeGeometry {
    /// Radii at 72, 36 and 24 samples.
    let outline72: [CGFloat]
    let outline36: [CGFloat]
    let outline24: [CGFloat]
    let sockets: [MochiSocket]
    /// Radius of the whole creature per direction, smoothed. Only things worn
    /// use this; the body is drawn from \`outline\`.
    let anchor24: [CGFloat]

    /// Half-extents and reach, in R.
    let rxK, ryK, top, bottom: CGFloat
    /// The face, replacing MochiConst for this shape.
    let eyeSp, eyeP: CGFloat
    /// Where things are worn: ears and horns at (earA0, earE0), everything on
    /// top of the head at crownE0.
    let earA0, earE0, crownE0: CGFloat
    let cheekK: CGFloat
    /// Hands and badge, measured off the outline rather than the bounding box.
    let handX, handY, badgeA0, badgeE0: CGFloat
    /// How much bigger this body's eyes are than the usual ones. Only a
    /// socketed body needs one — a pupil has to fill its eyeball.
    let eyeScale: CGFloat
    /// Motion. \`pivotY\` is the bottom the dance hops from, \`squashAnchorY\` the
    /// point a squash compresses toward, \`breathScale\` the correction that
    /// makes every shape's crown travel the same distance as classic's.
    let pivotY, squashAnchorY, breathScale: CGFloat

    /// True when the eyes live in sockets instead of on the head's sphere.
    var hasSockets: Bool { !sockets.isEmpty }

    func outline(lod: Int) -> [CGFloat] {
        lod >= 72 ? outline72 : (lod >= 36 ? outline36 : outline24)
    }
}

enum MochiShapeTable {
    static func geometry(_ shape: MochiShape) -> MochiShapeGeometry {
        switch shape {
${SHAPES.map((n) => `        case .${n}:${' '.repeat(8 - n.length)} return ${n}`).join('\n')}
        }
    }
`);
for (const n of SHAPES) {
  const g = shapes[n], a = g.a;
  const arr = (t) => '[' + g.r[t].map(f6).join(', ') + ']';
  sw.push(`
    static let ${n} = MochiShapeGeometry(
        outline72: ${arr(72)},
        outline36: ${arr(36)},
        outline24: ${arr(24)},
        sockets: [${g.sockets.map((k) => `MochiSocket(x: ${f6(k.x)}, y: ${f6(k.y)}, r: ${f6(k.r)})`).join(', ')}],
        anchor24: [${g.anchor.map(f6).join(', ')}],
        rxK: ${f6(a.rxK)}, ryK: ${f6(a.ryK)}, top: ${f6(a.top)}, bottom: ${f6(a.bottom)},
        eyeSp: ${f6(a.eyeSp)}, eyeP: ${f6(a.eyeP)},
        earA0: ${f6(a.earA0)}, earE0: ${f6(a.earE0)}, crownE0: ${f6(a.crownE0)},
        cheekK: ${f6(a.cheekK)},
        handX: ${f6(a.handX)}, handY: ${f6(a.handY)}, badgeA0: ${f6(a.badgeA0)}, badgeE0: ${f6(a.badgeE0)},
        eyeScale: ${f6(a.eyeScale)},
        pivotY: ${f6(a.pivotY)}, squashAnchorY: ${f6(a.squashAnchorY)}, breathScale: ${f6(a.breathScale)}
    )`);
}
sw.push('}', '');

// ---- TypeScript -----------------------------------------------------------
const ts = [];
ts.push(PREAMBLE('The tables'));
ts.push('', `export type MochiShape = ${SHAPES.map((n) => `'${n}'`).join(' | ')};

export const MOCHI_SHAPES: MochiShape[] = [${SHAPES.map((n) => `'${n}'`).join(', ')}];

export const MOCHI_SHAPE_LABEL: Record<MochiShape, string> = {
${SHAPES.map((n) => `  ${n}: '${LABEL[n]}',`).join('\n')}
};

export interface MochiSocket { x: number; y: number; r: number }

export interface MochiShapeGeometry {
  outline72: number[];
  outline36: number[];
  outline24: number[];
  sockets: MochiSocket[];
  anchor24: number[];
  rxK: number; ryK: number; top: number; bottom: number;
  eyeSp: number; eyeP: number;
  earA0: number; earE0: number; crownE0: number;
  cheekK: number;
  handX: number; handY: number; badgeA0: number; badgeE0: number;
  eyeScale: number;
  pivotY: number; squashAnchorY: number; breathScale: number;
}

export function shapeOutline(g: MochiShapeGeometry, lod: number): number[] {
  return lod >= 72 ? g.outline72 : lod >= 36 ? g.outline36 : g.outline24;
}

/**
 * Deterministic noise in 0…1, from an integer hash.
 *
 * An integer hash and not \`Math.sin(i * 127.1) * 43758.5\`: float \`sin\` differs
 * in its last bits between platforms, and the parity suite compares these
 * values against the Swift twin's.
 */
export function furHash(i: number, seed: number): number {
  let h = (Math.imul(i >>> 0, 0x9e3779b9) + seed) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0; h = Math.imul(h, 0x85ebca6b) >>> 0;
  h = (h ^ (h >>> 13)) >>> 0; h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return h / 0xffffffff;
}

/** How far out the head reaches in direction \`theta\` — for things worn. */
export function anchorRadius(theta: number, g: MochiShapeGeometry): number {
  const n = g.anchor24.length, twoPi = Math.PI * 2;
  const t = ((theta % twoPi) + twoPi) % twoPi;
  const f = (t / twoPi) * n;
  const i = Math.floor(f) % n;
  const a = g.anchor24[i], b = g.anchor24[(i + 1) % n];
  return a + (b - a) * (f - Math.floor(f));
}

// ── The plush tile ───────────────────────────────────────────────────────────
//
// The reference art gets its surface from an SVG filter — turbulence lit from
// one side and multiplied back over the shape — and none of that exists in
// Canvas 2D. What survives the translation is the part that matters: a fine,
// even grain that breaks up the gradient and reads as fibre rather than
// plastic. One tile, built once, shared by every engine and every colour,
// multiplied inside the body so each pal gets the same fibres in its own hue.

export const FUR_TILE_SIZE = 96;

/** Value noise on a wrapping grid, so the tile has no seam. */
function furNoise(x: number, y: number, cell: number): number {
  const gx = Math.floor(x / cell), gy = Math.floor(y / cell);
  const fx = (x % cell) / cell, fy = (y % cell) / cell;
  const wrap = FUR_TILE_SIZE / cell;
  const corner = (i: number, j: number) =>
    furHash(((j % wrap) * 57 + (i % wrap)) | 0, 0x5eed1234);
  // Smoothstep between corners: a linear blend leaves a visible lattice.
  const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  const top = corner(gx, gy) + (corner(gx + 1, gy) - corner(gx, gy)) * sx;
  const bot = corner(gx, gy + 1) + (corner(gx + 1, gy + 1) - corner(gx, gy + 1)) * sx;
  return top + (bot - top) * sy;
}

/** 0…255 grey, as the tile is written out. Shared with the parity dump. */
export function furSample(x: number, y: number): number {
  const v = furNoise(x, y, 12) * 0.62 + furNoise(x, y, 4) * 0.38;
  // Centred near white so multiplying darkens only slightly: this is a texture
  // on the body, not a shadow over it.
  return Math.max(0, Math.min(255, Math.round((0.80 + 0.26 * (v - 0.5)) * 255)));
}

let tile: HTMLCanvasElement | null | undefined;

/** The tile, built on first use. Null when there is no DOM (tests, Node). */
export function furTile(): HTMLCanvasElement | null {
  if (tile !== undefined) return tile;
  if (typeof document === "undefined") { tile = null; return tile; }
  const n = FUR_TILE_SIZE;
  const c = document.createElement("canvas");
  c.width = n; c.height = n;
  const x = c.getContext("2d");
  if (!x) { tile = null; return tile; }
  const img = x.createImageData(n, n);
  for (let y = 0; y < n; y++) {
    for (let px = 0; px < n; px++) {
      const v = furSample(px, y), o = (y * n + px) * 4;
      img.data[o] = v; img.data[o + 1] = v; img.data[o + 2] = v; img.data[o + 3] = 255;
    }
  }
  x.putImageData(img, 0, 0);
  tile = c;
  return tile;
}

export const MOCHI_SHAPE_TABLE: Record<MochiShape, MochiShapeGeometry> = {`);
for (const n of SHAPES) {
  const g = shapes[n], a = g.a;
  const arr = (t) => '[' + g.r[t].map(f6).join(', ') + ']';
  ts.push(`  ${n}: {
    outline72: ${arr(72)},
    outline36: ${arr(36)},
    outline24: ${arr(24)},
    sockets: [${g.sockets.map((k) => `{ x: ${f6(k.x)}, y: ${f6(k.y)}, r: ${f6(k.r)} }`).join(', ')}],
    anchor24: [${g.anchor.map(f6).join(', ')}],
    rxK: ${f6(a.rxK)}, ryK: ${f6(a.ryK)}, top: ${f6(a.top)}, bottom: ${f6(a.bottom)},
    eyeSp: ${f6(a.eyeSp)}, eyeP: ${f6(a.eyeP)},
    earA0: ${f6(a.earA0)}, earE0: ${f6(a.earE0)}, crownE0: ${f6(a.crownE0)},
    cheekK: ${f6(a.cheekK)},
    handX: ${f6(a.handX)}, handY: ${f6(a.handY)}, badgeA0: ${f6(a.badgeA0)}, badgeE0: ${f6(a.badgeE0)},
    eyeScale: ${f6(a.eyeScale)},
    pivotY: ${f6(a.pivotY)}, squashAnchorY: ${f6(a.squashAnchorY)}, breathScale: ${f6(a.breathScale)},
  },`);
}
ts.push('};', '');

if (process.argv.includes('--write')) {
  const { writeFileSync } = await import('node:fs');
  writeFileSync('NotchBuddy/Sources/App/MochiShape.swift', sw.join('\n'));
  writeFileSync('windows/src/mochi/shape.ts', ts.join('\n'));
  console.log('\nwrote NotchBuddy/Sources/App/MochiShape.swift and windows/src/mochi/shape.ts');
}

if (process.argv.includes('--svg')) {
  const TILE = 150, PAD = 10, COLS = 4;
  const COLOR = { classic: '#C4C5CA', round: '#1e88ff', boxy: '#8be22e', fluffy: '#ffc21a',
                  pointy: '#ff2fc4', heart: '#9d6bff', frog: '#ff7a2f' };
  const parts = [];
  order.forEach((name, i) => {
    const s2 = shapes[name], r = s2.r[72];
    const cx = PAD + (i % COLS) * (TILE + PAD) + TILE / 2;
    const cy = PAD + Math.floor(i / COLS) * (TILE + PAD) + TILE / 2;
    const k = TILE * 0.30;                       // same R = 0.3 * side the engine uses
    const pts = r.map((v, j) => {
      const t = j / r.length * 2 * Math.PI;
      return `${(cx + v * k * Math.cos(t)).toFixed(2)},${(cy + v * k * Math.sin(t)).toFixed(2)}`;
    }).join(' ');
    parts.push(`<rect x="${cx-TILE/2}" y="${cy-TILE/2}" width="${TILE}" height="${TILE}" rx="12" fill="#17181c"/>`);
    parts.push(`<polygon points="${pts}" fill="${COLOR[name]}"/>`);
    for (const k2 of s2.sockets) {
      parts.push(`<circle cx="${(cx + k2.x * k).toFixed(2)}" cy="${(cy + k2.y * k).toFixed(2)}" r="${(k2.r * k).toFixed(2)}" fill="${COLOR[name]}"/>`);
    }
    // Mochi's own silhouette, dotted, so the family resemblance is checkable.
    const cp = Array.from({ length: 72 }, (_, j) => {
      const t = j / 72 * 2 * Math.PI, ct = Math.cos(t), st = Math.sin(t);
      const x = CLASSIC.rx * (ct >= 0 ? Math.pow(ct, CLASSIC.exp) : -Math.pow(-ct, CLASSIC.exp));
      const y = CLASSIC.ry * (st >= 0 ? Math.pow(st, CLASSIC.exp) : -Math.pow(-st, CLASSIC.exp));
      return `${(cx + x * k).toFixed(2)},${(cy + y * k).toFixed(2)}`;
    }).join(' ');
    parts.push(`<polygon points="${cp}" fill="none" stroke="#ffffff" stroke-opacity=".28" stroke-width="1" stroke-dasharray="3 3"/>`);
    parts.push(`<text x="${cx}" y="${cy + TILE/2 - 8}" fill="#8a8f98" font-family="-apple-system,sans-serif" font-size="11" text-anchor="middle">${name}</text>`);
  });
  const W = PAD + COLS * (TILE + PAD), H = PAD + Math.ceil(order.length / COLS) * (TILE + PAD);
  const out = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><rect width="${W}" height="${H}" fill="#0d0e11"/>${parts.join('')}</svg>`;
  const { writeFileSync } = await import('node:fs');
  writeFileSync(process.argv[process.argv.indexOf('--svg') + 1] ?? 'mochi-shapes.svg', out);
  console.log('\nwrote contact sheet');
}
