// Ato's official mascot engine — "Actuar Bot v3", verbatim.
//
// Extracted 2026-11-15 from the hero of
//   https://blog.actuar.com/actuar/agora-voce-fala-com-a-gente-pelo-ato
// which embeds
//   https://blogworker-api.dev5014.workers.dev/Media/2026/11/capa-ato-71a922f2.html
// The same orb is the support launcher on novo.actuar.com.
//
// This file is the source of truth for NotchBuddy/Sources/App/AtoBot.swift and
// windows/src/ato/bot.ts. scripts/test-ato-bot.sh runs it under Node and holds
// both ports to its numbers, so never edit it to make a port pass: replace it
// with a newer copy from the site instead.
//
// Two scripts follow, unchanged. The first is the engine (window.ActuarBot6).
// The second is the blog's driver: the idle loop with a gesture every 6 s and
// the gaze that follows the pointer — what "Ato at rest" looks like.

/* Actuar Bot v3 — fiel ao Rostinho Actuar (cores, olhos, orbe em 3 camadas), com motor de estados.
   Coordenadas nativas do símbolo (486 × 477, centro 243,228). Pose = função pura do tempo. */
(function () {
  const TAU = Math.PI * 2, K = 100 / 196;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOut = t => 1 - Math.pow(1 - clamp(t), 3);
  const easeInOut = t => { t = clamp(t); return t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };
  const bump = (t, a, b) => (t <= a || t >= b) ? 0 : Math.sin(Math.PI * (t - a) / (b - a));
  const hash = n => { const x = Math.sin(n * 127.1 + .3) * 43758.5453; return x - Math.floor(x); };
  function spring(t, f = 2.2, z = .5) { if (t <= 0) return 0; const w = TAU * f, wd = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t)); }
  const kick = (t, f = 2.2, d = 4) => t <= 0 ? 0 : Math.exp(-d * t) * Math.sin(TAU * f * t);

  const SETA = {
    CHEV: "M174.8 34.9L19.5 242C7.4 257.9 2.1 275.8 2.1 293.2C2.1 310.2 6.9 326.1 15.7 340.2C16.1 339.7 16.6 338.7 17.1 338.2L172.4 131.2C189.8 108 215.9 96.3 241.6 96.3C267.7 96.3 293.8 108 310.8 131.2L466.1 338.2C467.5 339.7 469 341.6 469.9 343.6C490.2 314.5 492.7 274.4 468.5 242L313.2 34.9C295.8 11.7 270.1 0.1 244 0.1C217.9 0.1 192.2 11.7 174.8 34.9Z",
    BLUE: "M470 343.5C454.9 365.1 429.9 380.1 399.3 380.1C385 380.1 371.1 376.6 358.8 370C346.5 363.5 335.8 354 327.8 342.2C307.7 312.6 275.9 297.8 244.1 297.8C212.3 297.8 180.4 312.6 160.4 342.2C152.4 354 141.6 363.5 129.3 370C117 376.6 103.2 380.1 88.8 380.1C56.7 380.1 30.8 363.6 15.9 340.2C16.4 339.5 16.9 338.9 17.4 338.2L172.6 131.2C189.9 108.1 215.9 96.6 241.8 96.6C267.8 96.6 293.7 108.1 311 131.2L466.3 338.2C467.6 340 468.8 341.7 470 343.5Z",
    WAVE: "M397 476.3C382.7 476.3 368.8 472.8 356.5 466.2C344.2 459.7 333.5 450.2 325.4 438.3C305.4 408.7 273.6 393.8 241.8 393.8C210 393.8 178.2 408.7 158.1 438.3C150.1 450.2 139.4 459.7 127.1 466.2C114.8 472.8 100.9 476.3 86.6 476.3C35.4 476.3 0 434.2 0 389.3C0 372.5 5.1 355.5 16.1 339.9C30.9 363.3 56.7 379.7 88.8 379.7C103.2 379.7 117 376.2 129.3 369.6C141.6 363.1 152.4 353.6 160.4 341.7C180.4 312.1 212.2 297.3 244 297.3C275.8 297.3 307.6 312.1 327.7 341.7C335.7 353.6 346.5 363.1 358.8 369.6C371.1 376.2 384.9 379.7 399.3 379.7C429.8 379.7 454.7 364.7 469.9 343.1C506.3 399.8 466 476.3 397 476.3Z"
  };
  const BODIES = [{ id: 'orbe', label: 'Orbe' }, { id: 'seta', label: 'Seta' }];
  // orbe fiel: seta (laranja) atrás, onda (ciano) no meio, azul na frente; 88% de opacidade
  const ORB = [{ k: 'ch', R: 196, A: 14, n: 5, ph: 0, base: 0, dir: 1 }, { k: 'wv', R: 192, A: 12, n: 6, ph: 1.2, base: 20, dir: -1 }, { k: 'bl', R: 196, A: 13, n: 7, ph: 2.4, base: 40, dir: .7 }];
  const W = '#FFFFFF', INK = '#0A1130';
  const PALETTES = [
    { id: 'oficial', label: 'Oficial', ch: '#FB5423', bl: '#1B2FEB', wv: '#1FEFFF', sc: W, pu: INK, br: W },
    { id: 'noite', label: 'Noite', ch: '#0A1130', bl: '#1B2FEB', wv: '#0A1130', sc: W, pu: INK, br: W },
    { id: 'reverso', label: 'Reverso', ch: W, bl: '#1B2FEB', wv: W, sc: W, pu: INK, br: W },
    { id: 'oceano', label: 'Oceano', ch: '#1B2FEB', bl: '#0A1130', wv: '#1FEFFF', sc: W, pu: INK, br: '#1FEFFF' },
    { id: 'azul-laranja', label: 'Azul & Laranja', ch: '#1B2FEB', bl: '#FB5423', wv: '#0A1130', sc: W, pu: INK, br: W },
    { id: 'grafite', label: 'Grafite & Ciano', ch: '#2A3148', bl: '#0A1130', wv: '#1FEFFF', sc: W, pu: INK, br: '#1FEFFF' },
    { id: 'neon', label: 'Neon noturno', ch: '#1FEFFF', bl: '#1B2FEB', wv: '#FB5423', sc: W, pu: INK, br: W },
    { id: 'coral', label: 'Coral', ch: '#FF7A59', bl: '#0A1130', wv: '#FFC2A8', sc: W, pu: INK, br: '#FFC2A8' },
    { id: 'menta', label: 'Menta', ch: '#19C39C', bl: '#0A1130', wv: '#A6F3DE', sc: W, pu: INK, br: '#A6F3DE' },
    { id: 'lavanda', label: 'Lavanda', ch: '#8B7CF6', bl: '#2A1F7A', wv: '#CFC7FF', sc: W, pu: INK, br: '#CFC7FF' },
    { id: 'laranja', label: 'Laranja total', ch: '#FB5423', bl: '#C93B12', wv: '#FFB08F', sc: W, pu: INK, br: '#FFD9C9' },
    { id: 'indigo', label: 'Índigo DS', ch: '#9EA0F0', bl: '#4043DD', wv: '#282828', sc: W, pu: INK, br: W }
  ];
  const PAL_BY = Object.fromEntries(PALETTES.map(p => [p.id, p]));
  const EYE_STYLES = [{ id: 'pontinhos', label: 'Pontinhos' }];
  const EYX = 68, EY = -14;

  /* ---------------------------------------------------------------- olhos
     Esclera redonda + pupila de tinta com 2 brilhos + sobrancelha em arco (o Rostinho).
     Tudo numérico para interpolar: r, pr, pdx/pdy, lb (pálpebra de baixo), ut/us (de cima e inclinação),
     bl/bt/ba (sobrancelha), arc (olho feliz ∩), shut (fechado ∪). */
  const EYE = (o = {}) => Object.assign({ r: 38, sy: 1, pr: 22, pdx: 1, pdy: -1, lb: 26, ut: -60, us: 0, bl: -6, bt: 4, ba: 1, arc: 0, shut: 0 }, o);
  const pair = (o = {}, o2) => [EYE(o), EYE(o2 ? Object.assign({}, o, o2) : o)];
  const MO = (o = {}) => Object.assign({ a: 1, w: 21, c: 18, open: 0, dy: 16, dx: 0, rest: 1 }, o);
  const EXPRESSIONS = [
    { id: 'neutro', label: 'Padrão', eyes: pair(), mouth: MO() },
    { id: 'atento', label: 'Atencioso', eyes: pair({ r: 40, pdx: -3, pdy: 4, pr: 23, lb: 18 }), mouth: MO() },
    { id: 'curioso', label: 'Curioso', eyes: pair({ r: 34, pdx: 11, pdy: -6, pr: 20, lb: 32, bl: -6, bt: 4, ut: -30 }, { r: 44, pr: 23, bl: 16, bt: -2 }), mouth: MO({ w: 16, c: 10 }) },
    { id: 'surpreso', label: 'Surpreso', eyes: pair({ r: 45, pdx: 0, pdy: -8, pr: 25, lb: 30, bl: 18, bt: 4 }), mouth: MO({ w: 9, c: -13, open: 26, dy: 24 }) },
    { id: 'feliz', label: 'Feliz', eyes: pair({ arc: 1 }), mouth: MO() },
    { id: 'animado', label: 'Animado', eyes: pair({ arc: 1 }), mouth: MO({ w: 25, c: 0, open: 42, dy: 10 }) },
    { id: 'pronto', label: 'Prontinho', eyes: pair({ r: 40, pdx: 2, pdy: -6, pr: 23, lb: 16, bl: 10, bt: 3 }), mouth: MO({ w: 29, c: 26, dy: 36 }) },
    { id: 'olhao', label: 'Olhão', eyes: pair({ r: 42, pdx: 2, pdy: -5, pr: 25, lb: 60, bl: -2, bt: 5 }), mouth: MO() },
    { id: 'piscadela', label: 'Piscadela', eyes: pair({}, { arc: 1 }), mouth: MO({ w: 22, c: 20 }) },
    { id: 'bochechas', label: 'Bochechas', eyes: pair(), mouth: MO(), blush: 1, bs: 6 },
    { id: 'bravo', label: 'Bravo', eyes: pair({ pr: 20, ut: -22, us: 14, bl: -14, bt: -12, lb: 30 }), mouth: MO({ w: 16, c: -8 }) },
    { id: 'triste', label: 'Triste', eyes: pair({ r: 38, pdx: 2, pdy: 10, pr: 20, ut: -24, us: -18, lb: 60 }), mouth: MO({ w: 16, c: -10, dy: 22 }), tear: 1, droop: 1, look: { x: 0, y: .8 } },
    { id: 'assustado', label: 'Assustado', eyes: pair({ r: 42, pr: 13, pdx: 0, pdy: 0, lb: 60, bl: 16, bt: 2 }), mouth: MO({ w: 10, c: -12, open: 24, dy: 24 }) },
    { id: 'desconfiado', label: 'Desconfiado', eyes: pair({ pdx: 12, ut: -26, us: 0, bl: -6, bt: 4 }, { ut: -8, us: 6, bl: -14, bt: -6 }), mouth: MO({ w: 14, c: -4, dx: 8 }) },
    { id: 'sonolento', label: 'Sonolento', eyes: pair({ pdy: 8, ut: -14, us: -4, lb: 22, bl: -6, bt: 4 }), mouth: MO({ w: 12, c: 6 }) },
    { id: 'timido', label: 'Tímido', eyes: pair({ pdx: -10, pdy: 9, pr: 20, lb: 20 }), mouth: MO({ w: 12, c: 8 }), blush: 1 }
  ];
  const EXPR_BY = Object.fromEntries(EXPRESSIONS.map(e => [e.id, e]));
  const face = (id, over = {}) => { const e = EXPR_BY[id]; return Object.assign({ eyes: e.eyes.map(x => Object.assign({}, x)), mouth: Object.assign({}, e.mouth), blush: e.blush || 0, tear: e.tear || 0, droop: e.droop || 0 }, over); };
  const withEyes = (id, o, o2) => face(id).eyes.map((e, i) => Object.assign(e, o, i && o2 ? o2 : {}));

  function base(X) {
    const ex = X.expr || EXPRESSIONS[0];
    return { r: 1, sx: 1, sy: 1, x: 0, y: 0, roll: 0, anchor: 0, gray: 0, look: Object.assign({ x: 0, y: 0 }, ex.look),
      eyes: ex.eyes.map(e => Object.assign({}, e)), eyeA: 1, mouth: Object.assign({}, ex.mouth), blush: ex.blush || 0, bs: ex.bs || 0, bp: ex.bp, tear: ex.tear || 0, droop: ex.droop || 0,
      twist: 0, wob: 1, spread: 0, lay: [0, 1, 2].map(() => ({ x: 0, y: 0, s: 1, a: 1, m: 0 })), fo: { x: 0, y: 0 }, eyeS: 1, decor: [], drift: 1, breathe: 1, blinkOK: 1, gazeFree: 0 };
  }
  function full(S, t, X) {
    const P = base(X), o = S.pose(t, X) || {};
    for (const k in o) { if (k === 'mouth' || k === 'look' || k === 'fo') P[k] = Object.assign({}, P[k], o[k]); else if (k === 'lay') P.lay = P.lay.map((l, i) => Object.assign({}, l, o.lay[i] || {})); else P[k] = o[k]; }
    return P;
  }
  const talk = t => { const s = t * 7.6; return Math.abs(Math.sin(s)) * (.55 + .45 * Math.sin(s * .37 + 1)) * (.35 + .65 * Math.abs(Math.sin(t * 1.9))); };

  const STATES = [
    { id: 'idle', label: 'Repouso', trigger: 'Widget aberto, sem atividade', dur: 3.2, pt: 1, f: 2.2, z: .5, blinkIn: 1,
      moves: 'Camadas girando devagar em sentidos opostos, ondas fluindo, piscadas e pupilas vagando.', pose: () => ({ gazeFree: 1 }) },
    { id: 'follow', label: 'Seguir o cursor', trigger: 'Cursor sobre o widget ou o launcher', dur: 3.2, pt: .9, f: 2.4, z: .45, blinkIn: 1,
      moves: 'Pupilas e rosto seguem o ponteiro; as camadas giram levemente na direção do olhar.',
      pose: (t, X) => { const s = { x: Math.sin(t * 1.7), y: .7 * Math.sin(t * 3.4) }; const w = X.pointer && X.follow ? (X.followW ?? 1) : 0; const lk = { x: lerp(s.x, w ? X.pointer.x : s.x, w), y: lerp(s.y, w ? X.pointer.y : s.y, w) }; return Object.assign(face('atento'), { drift: 0, look: lk, twist: lk.x * 14, roll: lk.x * 4 }); } },
    { id: 'listening', label: 'Ouvindo', trigger: 'Usuário digitando no campo', dur: 3, pt: .4, f: 2.4, z: .45, blinkIn: 1,
      moves: 'Olha para o campo e acena no ritmo da digitação; cada aceno dá um tranco nas camadas.',
      pose: t => { const n = Math.pow(Math.abs(Math.sin(t * Math.PI * 1.3)), 3); return Object.assign(face('atento'), { look: { x: -.7, y: 1 }, roll: -7, y: .03 * n, sy: 1 - .04 * n, sx: 1 + .03 * n, anchor: 1, drift: .3, twist: 8 * n, spread: .05 * n }); } },
    { id: 'thinking', label: 'Pensando', trigger: 'Aguardando a resposta da automação', dur: 3.2, pt: 1, f: 2, z: .45, blinkIn: 0,
      moves: 'Encolhe, olha para o alto e as 3 camadas giram rápido, cada uma para um lado.',
      pose: t => Object.assign(face('curioso'), { r: .88, look: { x: .9 + .2 * Math.sin(t * 1.3), y: -1 }, roll: 6, drift: 0, twist: t * 120, wob: 1.5, spread: .04 + .03 * Math.sin(t * 5), mouth: MO({ w: 12, c: 4, rest: 0 }) }) },
    { id: 'searching', label: 'Buscando · 1', trigger: 'knowledge_search · Procurando na central de ajuda…', dur: 3.2, pt: 1, f: 2, z: .45, blinkIn: 0,
      moves: 'Encolhe, olha para o alto e as 3 camadas giram rápido, cada uma para um lado.',
      pose: t => Object.assign(face('curioso'), { r: .88, look: { x: .9 + .2 * Math.sin(t * 1.3), y: -1 }, roll: 6, drift: 0, twist: t * 120, wob: 1.5, spread: .04 + .03 * Math.sin(t * 5), mouth: MO({ w: 12, c: 4, rest: 0 }) }) },
    { id: 'searching2', label: 'Buscando · 2', trigger: 'knowledge_search · Procurando na central de ajuda…', dur: 3.2, pt: 1, f: 2, z: .45, blinkIn: 0,
      moves: 'Encolhe, olha para o alto e as 3 camadas giram rápido, cada uma para um lado.',
      pose: t => Object.assign(face('curioso'), { r: .88, look: { x: .9 + .2 * Math.sin(t * 1.3), y: -1 }, roll: 6, drift: 0, twist: t * 120, wob: 1.5, spread: .04 + .03 * Math.sin(t * 5), mouth: MO({ w: 12, c: 4, rest: 0 }) }) },
    { id: 'searching3', label: 'Buscando · 3', trigger: 'knowledge_search · Procurando na central de ajuda…', dur: 3.2, pt: 1, f: 2, z: .45, blinkIn: 0,
      moves: 'Encolhe, olha para o alto e as 3 camadas giram rápido, cada uma para um lado.',
      pose: t => Object.assign(face('curioso'), { r: .88, look: { x: .9 + .2 * Math.sin(t * 1.3), y: -1 }, roll: 6, drift: 0, twist: t * 120, wob: 1.5, spread: .04 + .03 * Math.sin(t * 5), mouth: MO({ w: 12, c: 4, rest: 0 }) }) },
    { id: 'searching4', label: 'Buscando · 4', trigger: 'knowledge_search · Procurando na central de ajuda…', dur: 3.2, pt: 1, f: 2, z: .45, blinkIn: 0,
      moves: 'Encolhe, olha para o alto e as 3 camadas giram rápido, cada uma para um lado.',
      pose: t => Object.assign(face('curioso'), { r: .88, look: { x: .9 + .2 * Math.sin(t * 1.3), y: -1 }, roll: 6, drift: 0, twist: t * 120, wob: 1.5, spread: .04 + .03 * Math.sin(t * 5), mouth: MO({ w: 12, c: 4, rest: 0 }) }) },
    { id: 'speaking', label: 'Respondendo', trigger: 'Mensagem da automação chegando', dur: 3, pt: .22, f: 2.4, z: .5, blinkIn: 1,
      moves: 'Fala em sílabas; o corpo quica e as camadas balançam a cada sílaba.',
      pose: t => { const v = talk(t); return Object.assign(face('neutro'), { mouth: MO({ w: 19 + 5 * v, c: 14 - 6 * v, open: 4 + 24 * v, dy: 12, rest: 0 }), y: -.03 * v, sy: 1 + .035 * v, sx: 1 - .025 * v, anchor: 1, gazeFree: 1, twist: 10 * v, spread: .05 * v }); } },
    { id: 'writing', label: 'Pensando', trigger: 'Automação pensando, buscando e redigindo a resposta', dur: 3.2, pt: .5, f: 2.4, z: .5, blinkIn: 1,
      moves: 'Olha para baixo e percorre a linha da esquerda para a direita; a cada palavra as camadas dão um tique, e na quebra de linha o olhar volta rápido para o início.',
      pose: t => { const L = 1.05, q = (t % L) / L, ret = q > .86, sw = ret ? 1 - (q - .86) / .14 : q / .86, tk = Math.pow(Math.abs(Math.sin(t * Math.PI * 5.2)), 6) * (ret ? 0 : 1);
        return Object.assign(face('atento'), { look: { x: -.85 + 1.7 * sw, y: .85 }, roll: -4 + 8 * sw, x: .025 * (sw - .5), y: .02 + .012 * tk, sy: 1 - .025 * tk, sx: 1 + .02 * tk, anchor: 1, drift: 0, twist: 14 * sw + 6 * tk, spread: .03 * tk, mouth: MO({ w: 10, c: 2, rest: 0 }) }); } },
    { id: 'notify', label: 'Nova mensagem', trigger: 'Mensagem nova com o widget fechado', dur: 2.6, pt: .7, f: 2.6, z: .4, blinkIn: 1,
      moves: 'Pula com mola, o badge surge com overshoot, as camadas dão meia-volta e os olhos vão até o badge.',
      pose: t => { const m = easeInOut((t - 1.3) / .45); return Object.assign(face('surpreso'), { r: 1 + .12 * kick(t, 2.2, 4), look: { x: lerp(1, 0, m), y: lerp(-1, 0, m) }, drift: m, twist: 60 * easeOut(t / .6) - 60 * m, mouth: MO({ w: 9, c: -13, open: 26, dy: 24, rest: 0, a: 1 - m }), decor: [{ type: 'badge', x: .74, y: -.74, r: Math.max(0, .21 * spring(t - .12, 2.4, .35)), a: 1 }] }); } },
    { id: 'handoff', label: 'Transferindo', trigger: 'Conversa passando para um atendente', dur: 3.4, pt: 1.7, f: 1.8, z: .55, blinkIn: 0,
      moves: 'Vai para o lado girando, o atendente surge com mola e as camadas viajam de um para o outro.',
      pose: t => { const k = spring(t, 1.6, .55), h = Math.max(0, spring(t - .35, 1.8, .42)); const dots = [0, 1, 2].map(i => { const p = ((t * .8 - i * .22) % 1 + 1) % 1; return { type: 'dot', x: lerp(-.28, .56, p), y: -.62 - .28 * Math.sin(Math.PI * p), r: .055, a: clamp((t - .7) / .3) * Math.sin(Math.PI * p) }; }); return Object.assign(face('neutro'), { x: -.62 * k, r: 1 - .34 * k, look: { x: 1, y: -.2 }, drift: 0, twist: -90 * k, mouth: MO({ rest: 0 }), decor: [{ type: 'human', x: .8, y: .08, r: .46 * h, a: clamp(h * 2) }] }); } },
    { id: 'success', label: 'Resolvido', trigger: 'Atendimento resolvido ou avaliação positiva', dur: 2.6, pt: .45, f: 2.2, z: .5, blinkIn: 0,
      moves: 'Agacha, pula com squash & stretch dando uma volta inteira nas camadas e aterrissa com mola.',
      pose: t => { const ant = bump(t, 0, .22), air = t > .2 && t < .78 ? Math.sin(Math.PI * (t - .2) / .58) : 0; let sy = 1 - .07 * ant; if (air > 0) sy = 1 + .04 * (1 - air) * (t < .49 ? 1 : 0) + .015 * air; if (t >= .78) sy = 1 - .07 * Math.exp(-6 * (t - .78)) * Math.cos(TAU * 2.4 * (t - .78)); return Object.assign(face('animado'), { y: -.2 * air, sy, sx: 1 + (1 - sy) * .6, anchor: 1, drift: 0, twist: 360 * easeInOut((t - .15) / .9), spread: .1 * air, wob: 1 + .3 * air, mouth: MO({ w: 25, c: 0, open: 42, dy: 10, rest: 0 }) }); } },
    { id: 'success2', label: 'Resolvido · A', trigger: 'Atendimento resolvido ou avaliação positiva', dur: 2.6, pt: .45, f: 2.2, z: .5, blinkIn: 0,
      moves: 'Agacha, pula com squash & stretch dando uma volta inteira nas camadas e aterrissa com mola.',
      pose: t => { const ant = bump(t, 0, .22), air = t > .2 && t < .78 ? Math.sin(Math.PI * (t - .2) / .58) : 0; let sy = 1 - .16 * ant; if (air > 0) sy = 1 + .1 * (1 - air) * (t < .49 ? 1 : 0) + .04 * air; if (t >= .78) sy = 1 - .17 * Math.exp(-6 * (t - .78)) * Math.cos(TAU * 2.4 * (t - .78)); return Object.assign(face('animado'), { y: -.44 * air, sy, sx: 1 + (1 - sy) * .9, anchor: 1, drift: 0, twist: 360 * easeInOut((t - .15) / .9), spread: .1 * air, wob: 1 + .6 * air, mouth: MO({ w: 25, c: 0, open: 42, dy: 10, rest: 0 }) }); } },
    { id: 'success3', label: 'Resolvido · B', trigger: 'Atendimento resolvido ou avaliação positiva', dur: 2.6, pt: .45, f: 2.2, z: .5, blinkIn: 0,
      moves: 'Agacha, pula com squash & stretch dando uma volta inteira nas camadas e aterrissa com mola.',
      pose: t => { const ant = bump(t, 0, .22), air = t > .2 && t < .78 ? Math.sin(Math.PI * (t - .2) / .58) : 0; let sy = 1 - .16 * ant; if (air > 0) sy = 1 + .1 * (1 - air) * (t < .49 ? 1 : 0) + .04 * air; if (t >= .78) sy = 1 - .17 * Math.exp(-6 * (t - .78)) * Math.cos(TAU * 2.4 * (t - .78)); return Object.assign(face('animado'), { y: -.44 * air, sy, sx: 1 + (1 - sy) * .9, anchor: 1, drift: 0, twist: 360 * easeInOut((t - .15) / .9), spread: .1 * air, wob: 1 + .6 * air, mouth: MO({ w: 25, c: 0, open: 42, dy: 10, rest: 0 }) }); } },
    { id: 'success4', label: 'Resolvido · C', trigger: 'Atendimento resolvido ou avaliação positiva', dur: 2.6, pt: .45, f: 2.2, z: .5, blinkIn: 0,
      moves: 'Agacha, pula com squash & stretch dando uma volta inteira nas camadas e aterrissa com mola.',
      pose: t => { const ant = bump(t, 0, .22), air = t > .2 && t < .78 ? Math.sin(Math.PI * (t - .2) / .58) : 0; let sy = 1 - .16 * ant; if (air > 0) sy = 1 + .1 * (1 - air) * (t < .49 ? 1 : 0) + .04 * air; if (t >= .78) sy = 1 - .17 * Math.exp(-6 * (t - .78)) * Math.cos(TAU * 2.4 * (t - .78)); return Object.assign(face('animado'), { y: -.44 * air, sy, sx: 1 + (1 - sy) * .9, anchor: 1, drift: 0, twist: 360 * easeInOut((t - .15) / .9), spread: .1 * air, wob: 1 + .6 * air, mouth: MO({ w: 25, c: 0, open: 42, dy: 10, rest: 0 }) }); } },
    { id: 'error', label: 'Não entendi', trigger: 'Automação não entendeu a mensagem', dur: 2.6, pt: .55, f: 2.4, z: .45, blinkIn: 1,
      moves: 'Balança a cabeça com amortecimento, camadas tremendo e um “?” que surge com mola.',
      pose: t => { const sh = t > .1 ? Math.sin(TAU * 3.6 * (t - .1)) * Math.exp(-2.6 * (t - .1)) : 0; return Object.assign(face('curioso', { eyes: pair({ r: 39, pdx: 4, pdy: -5, pr: 20, lb: 32, bl: 4, bt: 3 }) }), { x: .12 * sh, roll: 9 * sh, drift: .4, twist: 25 * sh, mouth: MO({ w: 13, c: -6, dx: 6, rest: 0 }), decor: [{ type: 'text', txt: '?', x: .9, y: -.78, s: .62 * Math.max(0, spring(t - .3, 2.2, .35)), a: clamp((t - .3) / .15) }] }); } },
    { id: 'offline', label: 'Fora do horário', trigger: 'Equipe fora do horário de atendimento', dur: 3, pt: 1, f: 1.6, z: .7, blinkIn: 1,
      moves: 'Perde a cor, afunda e fica com as pálpebras baixas. Camadas quase paradas.',
      pose: () => Object.assign(face('sonolento'), { gray: 1, r: .92, y: .05, look: { x: 0, y: .6 }, drift: .3, breathe: 1.6, wob: .5 }) },
    { id: 'sleep', label: 'Dormindo', trigger: '60 s sem interação', dur: 3.4, pt: .8, f: 1.4, z: .7, blinkIn: 0,
      moves: 'Olhos fechados, respiração funda (squash lento), camadas respirando juntas e “z” flutuando.',
      pose: t => { const b = Math.sin(t * TAU / 2.6); return Object.assign(face('neutro', { eyes: pair({ shut: 1 }) }), { mouth: MO({ w: 12, c: 6, dy: 22 }), sy: 1 + .05 * b, sx: 1 - .038 * b, anchor: 1, drift: .55, blinkOK: 0, wob: 1 + .08 * b, decor: [0, 1, 2].map(i => { const p = ((t / 2.6 + i / 3) % 1 + 1) % 1; return { type: 'text', txt: 'z', x: .6 + .3 * p, y: -.62 - .56 * p, s: .22 + .2 * p, a: Math.sin(Math.PI * p) * .85 }; }) }); } },
    { id: 'welcome', label: 'Boas-vindas', trigger: 'Primeira abertura do widget', dur: 3, pt: 1.8, f: 2, z: .45, blinkIn: 0,
      moves: 'Nasce de um ponto girando as camadas em espiral, abre os olhos e dá uma piscadela.',
      pose: t => { const g = spring(t - .1, 1.5, .36), eo = clamp((t - .55) / .2), wk = clamp((t - 1.5) / .1) * (1 - clamp((t - 2.05) / .15)); return Object.assign(face('neutro', { eyes: pair({ sy: Math.max(.06, eo) }, { sy: Math.max(.06, eo), arc: wk }) }), { r: Math.max(.06, .08 + .92 * g), mouth: MO({ w: 22, c: 20, a: clamp((t - .75) / .3), rest: 0 }), drift: 0, blinkOK: 0, twist: -540 * (1 - easeOut(t / 1.5)), wob: 1.4 }); } },
    { id: 'goodbye', label: 'Despedida', trigger: 'Minimizar ou encerrar a conversa', dur: 2.6, pt: .7, f: 2.2, z: .5, blinkIn: 0,
      moves: 'Piscadela com sorriso, estica para cima e encolhe girando até virar um ponto.',
      pose: t => { const wk = clamp((t - .2) / .1) * (1 - clamp((t - .85) / .15)), st = bump(t, 1.15, 1.5), c = Math.max(0, spring(t - 1.45, 2, .5)); return Object.assign(face('neutro', { eyes: pair({}, { arc: wk }) }), { mouth: MO({ w: 22, c: 20, a: 1 - clamp((t - 1.3) / .2), rest: 0 }), sy: 1 + .14 * st, sx: 1 - .1 * st, anchor: 1, r: Math.max(.08, 1 - .9 * c), y: .3 * c, eyeA: 1 - clamp((t - 1.35) / .25), drift: 0, blinkOK: 0, twist: 400 * c }); } },
  ];
  const STATE_BY = Object.fromEntries(STATES.map(s => [s.id, s]));

  const mixObj = (a, b, k) => { const o = {}; for (const key in b) o[key] = typeof b[key] === 'number' ? lerp(a[key] ?? b[key], b[key], k) : b[key]; return o; };
  function mixPose(a, b, k, kc) {
    const L = (key, kk = k) => lerp(a[key], b[key], kk);
    return { r: L('r'), sx: L('sx'), sy: L('sy'), x: L('x'), y: L('y'), roll: L('roll'), anchor: L('anchor', kc), gray: L('gray', kc),
      look: mixObj(a.look, b.look, k), eyes: [mixObj(a.eyes[0], b.eyes[0], k), mixObj(a.eyes[1], b.eyes[1], k)], eyeA: L('eyeA', kc),
      mouth: mixObj(a.mouth, b.mouth, k), blush: L('blush', kc), bs: b.bs || 0, bp: b.bp, tear: L('tear', kc), droop: L('droop', kc), twist: L('twist', kc), wob: L('wob'), spread: L('spread'), lay: a.lay.map((l, i) => mixObj(l, b.lay[i], k)), fo: mixObj(a.fo, b.fo, k), eyeS: L('eyeS'),
      decor: a.decor.map(d => Object.assign({}, d, { a: d.a * (1 - kc) })).concat(b.decor.map(d => Object.assign({}, d, { a: d.a * kc }))),
      drift: L('drift', kc), breathe: L('breathe', kc), blinkOK: b.blinkOK, gazeFree: b.gazeFree };
  }
  function blink(T) {
    const P = 4.1, k = Math.floor(T / P);
    for (const kk of [k - 1, k]) {
      const t0 = kk * P + hash(kk) * 2.2, d = T - t0;
      if (d >= 0 && d < .2) return 1 - Math.sin(Math.PI * d / .2) * .94;
      if (hash(kk + 99) > .68) { const d2 = d - .32; if (d2 >= 0 && d2 < .18) return 1 - Math.sin(Math.PI * d2 / .18) * .94; }
    }
    return 1;
  }
  function post(P, T, tl, S, X, noBlink) {
    const bl = noBlink ? 1 : (P.blinkOK ? blink(T) : 1) * (S && S.blinkIn && tl < .22 ? 1 - Math.sin(Math.PI * tl / .22) * .94 : 1);
    P.eyes = P.eyes.map(e => Object.assign({}, e, { sy: e.sy * bl }));
    const d = P.drift;
    P.look = { x: P.look.x + d * (.35 * Math.sin(T * .71) + .2 * Math.sin(T * 1.93 + 1)), y: P.look.y + d * (.25 * Math.sin(T * .93 + 2) + .1 * Math.sin(T * 2.3)) };
    if (X.follow && X.pointer && P.gazeFree) { const w = .85 * (X.followW ?? 1); P.look = { x: lerp(P.look.x, X.pointer.x, w), y: lerp(P.look.y, X.pointer.y, w) }; }
    if (P.droop > .01) { const dr = P.droop, sg = Math.sin(T * TAU / 4.2); P.y += .06 * dr; P.sy *= 1 - .05 * dr + .012 * sg * dr; P.sx *= 1 + .035 * dr; P.anchor = Math.max(P.anchor, dr); P.twist *= 1 - .7 * dr; P.wob = lerp(P.wob, .55, dr); }
    const en = X.energy ?? 1, br = Math.sin(T * TAU / (3.4 * (P.breathe || 1)));
    P.sx = 1 + (P.sx * (1 - .01 * br) - 1) * en; P.sy = 1 + (P.sy * (1 + .016 * br) - 1) * en; P.y *= en; P.twist *= en; P.wob = 1 + (P.wob - 1) * en;
    P.T = T; P.energy = en;
    return P;
  }
  const total = blocks => blocks.reduce((s, b) => s + b.dur, 0);
  function sample(T, blocks, X) {
    const tot = total(blocks); if (!blocks.length || tot <= 0) return post(full(STATES[0], T, X), T, 1, null, X);
    const w = ((T % tot) + tot) % tot; let acc = 0, i = 0;
    for (; i < blocks.length; i++) { if (w < acc + blocks[i].dur) break; acc += blocks[i].dur; }
    i = Math.min(i, blocks.length - 1);
    const S = STATE_BY[blocks[i].state], tl = w - acc; let P = full(S, tl, X);
    if (tl < 1.1) { const pb = blocks[(i - 1 + blocks.length) % blocks.length]; P = mixPose(full(STATE_BY[pb.state], pb.dur, X), P, spring(tl, S.f, S.z), easeInOut(tl / .5)); }
    P.twist += 38 * kick(tl, 1.3, 3.2); // giro de transição: toda troca de estado torce as camadas
    return post(P, T, tl, S, X);
  }
  function poseAt(stateId, t, X, noBlink = true) { const S = STATE_BY[stateId]; return post(full(S, t, X), noBlink ? 1.3 : t, 1, S, X, noBlink); }

  /* ---------------------------------------------------------------- render */
  const f1 = n => Math.round(n * 10) / 10;
  function wav(R, A, n, ph) { let d = ''; for (let i = 0; i <= 120; i++) { const t = i / 120 * TAU, r = R + A * Math.sin(n * t + ph); d += (i ? 'L' : 'M') + f1(r * Math.cos(t)) + ' ' + f1(r * Math.sin(t)); } return d + 'Z'; }
  function hexMix(a, b, t) {
    const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
    const ch = sh => Math.round(lerp((pa >> sh) & 255, (pb >> sh) & 255, clamp(t)));
    return '#' + ((1 << 24) + (ch(16) << 16) + (ch(8) << 8) + ch(0)).toString(16).slice(1);
  }
  // olho = UMA forma branca: elipse recortada pelas linhas das pálpebras (sem sobreposição de cor, sem borda)
  function eyeShape(x, y, r, ry, e, sd) {
    const pts = [], N = 72;
    for (let i = 0; i < N; i++) {
      const a = i / N * TAU; let px = x + Math.cos(a) * r, py = y + Math.sin(a) * ry;
      const u = (px - x) / r;
      if (e.ut > -44) { const top = y + e.ut - e.us * sd * u; if (py < top) py = top; }
      if (e.lb < 44) { const bot = y + e.lb - 10 * (1 - u * u); if (py > bot) py = bot; }
      pts.push([px, py]);
    }
    return 'M' + pts.map(p => f1(p[0]) + ' ' + f1(p[1])).join('L') + 'Z';
  }
  const PAPER = { claro: '#FFFFFF', escuro: '#1D1E1F' };
  function render(P, o = {}) {
    const size = o.size || 160, px = size * 1.6, uid = o.uid || 'ab', dark = o.bg === 'escuro', paper = PAPER[o.bg] || '#FFFFFF';
    const p0 = o.pal || PALETTES[0], g = dark ? '#6B7079' : '#B3B8C0', gm = c => hexMix(c, g, P.gray);
    const pal = { ch: gm(p0.ch), bl: gm(p0.bl), wv: gm(p0.wv), sc: p0.sc, pu: p0.pu, br: gm(p0.br) };
    const style = 'pontinhos', T = P.T || 0; // projeto ato: só olhos de pontinho
    const s = K * P.r, A = P.anchor * 100 * P.r;
    let out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-160 -160 320 320" width="${f1(px)}" height="${f1(px)}" style="display:block;overflow:visible">`;
    if (!o.noPaper) out += `<rect x="-160" y="-160" width="320" height="320" fill="${paper}"/>`;
    out += `<g transform="translate(${f1(P.x * 100)} ${f1(P.y * 100)}) rotate(${f1(P.roll)}) translate(0 ${f1(A)}) scale(${P.sx.toFixed(3)} ${P.sy.toFixed(3)}) translate(0 ${f1(-A)}) scale(${s.toFixed(4)})">`;
    if ((o.body || 'orbe') === 'orbe') {
      out += `<g style="isolation:isolate">`;
      ORB.forEach((L, i) => {
        const rot = L.base + L.dir * (P.twist + T * 7 * (P.energy ?? 1)) + (P.lay[i].rot || 0), sc = 1 + P.spread * (i - 1) * .6;
        const d = wav(L.R * sc, L.A * P.wob * (1 + .12 * Math.sin(T * 1.4 + i * 2)), L.n, L.ph + T * .35 * L.dir);
        const ly = P.lay[i], px = ly.x + P.look.x * (i - 1) * 9, py = ly.y + P.look.y * (i - 1) * 6;
        out += `<path d="${d}" fill="${pal[L.k]}" opacity="${(.88 * clamp(ly.a)).toFixed(2)}" transform="translate(${f1(px)} ${f1(py)}) scale(${Math.max(0, ly.s).toFixed(3)}) rotate(${f1(rot)})"/>`;
      });
      out += `</g>`;
    } else {
      // a seta é um símbolo rígido: as 3 partes se movem juntas (sem frestas); o giro vira uma inclinação suave
      const bob = Math.sin(T * 1.1) * 3 * P.wob, tw = Math.sin(P.twist * Math.PI / 180) * 5, pulse = 1 + P.spread * .35;
      out += `<g transform="translate(0 ${f1(-bob)}) rotate(${f1(tw)} 0 40) scale(${pulse.toFixed(3)}) translate(-243 -228)" stroke-linejoin="round">`;
      [['CHEV', 'ch', 0, 243, 170], ['BLUE', 'bl', 2, 243, 240], ['WAVE', 'wv', 1, 243, 392]].forEach(([pk, ck, li, rx, ry]) => { const l = P.lay[li], rcx = rx - 243, rcy = ry - 228, cx = rcx * (1 - l.m) + l.x + P.look.x * (li - 1) * 8, cy = rcy * (1 - l.m) + l.y; out += `<g opacity="${clamp(l.a).toFixed(2)}" transform="${l.u != null ? `translate(${f1(l.x + P.look.x * (li - 1) * 8 + 243)} ${f1(l.y + 228)}) scale(${Math.max(0, l.u).toFixed(3)}) translate(-243 -228)` : `translate(${f1(cx + 243)} ${f1(cy + 228)}) scale(${Math.max(0, l.s).toFixed(3)}) translate(${-rx} ${-ry})`}"><path d="${SETA[pk]}" fill="${pal[ck]}" stroke="${pal[ck]}" stroke-width="${pk === 'BLUE' ? 2.5 : 1.5}"/></g>`; });
      out += `</g>`;
    }
    const fx = P.look.x * 7, fy = P.look.y * 5;
    out += `<g opacity="${clamp(P.eyeA).toFixed(2)}" transform="translate(${f1(fx + P.fo.x)} ${f1(fy + P.fo.y)}) translate(0 ${EY}) scale(${P.eyeS.toFixed(3)}) translate(0 ${-EY})">`;
    if (P.blush > .01) { const b = P.blush, bs = P.bs || 0, PK = '#FFA3BC'; [-1, 1].forEach(sd => { const cx = sd * 112, cy = 40;
      if (bs === 6) { const gid = `${uid}bg${sd > 0 ? 1 : 0}`, C6 = '#FFB4C4'; out += `<defs><radialGradient id="${gid}"><stop offset="0" stop-color="${C6}" stop-opacity="${b.toFixed(2)}"/><stop offset=".62" stop-color="${C6}" stop-opacity="${(b * .92).toFixed(2)}"/><stop offset="1" stop-color="${C6}" stop-opacity="0"/></radialGradient></defs><ellipse cx="${sd * (P.bp || [118, 46, 26, 15])[0]}" cy="${(P.bp || [118, 46, 26, 15])[1]}" rx="${(P.bp || [118, 46, 26, 15])[2]}" ry="${(P.bp || [118, 46, 26, 21])[3]}" fill="url(#${gid})"/>`; }
      else if (bs === 1) out += `<ellipse cx="${sd * 104}" cy="34" rx="20" ry="11" fill="${pal.ch}" opacity="${(b * .85).toFixed(2)}"/>`;
      else if (bs === 2) [-1, 0, 1].forEach(k => { const x = cx + k * 17; out += `<line x1="${x + 7}" y1="${cy - 13}" x2="${x - 7}" y2="${cy + 13}" stroke="${PK}" stroke-width="8" stroke-linecap="round" opacity="${(b * .95).toFixed(2)}"/>`; });
      else if (bs === 3) [[-15, -5], [13, -7], [0, 12]].forEach(([dx, dy]) => { out += `<circle cx="${cx + dx}" cy="${cy + dy}" r="8.5" fill="${PK}" opacity="${(b * .95).toFixed(2)}"/>`; });
      else if (bs === 4) out += `<ellipse cx="${cx}" cy="${cy + 2}" rx="40" ry="22" fill="${PK}" opacity="${(b * .28).toFixed(2)}"/><ellipse cx="${cx}" cy="${cy + 2}" rx="26" ry="14" fill="${PK}" opacity="${(b * .45).toFixed(2)}"/>`;
      else if (bs === 5) out += `<ellipse cx="${cx}" cy="${cy}" rx="26" ry="15" fill="none" stroke="${PK}" stroke-width="7" opacity="${(b * .9).toFixed(2)}"/>`;
      else out += `<ellipse cx="${sd * 125}" cy="38" rx="26" ry="15" fill="${PK}" opacity="${(b * .7).toFixed(2)}"/>`; }); }
    if (P.tear > .01) { const tp = ((T / 2.4) % 1 + 1) % 1, ty = EY + 30 + tp * 46, tx = -EYX - 22, ta = P.tear * Math.sin(Math.PI * Math.min(1, tp * 1.15)); out += `<g transform="translate(${tx} ${f1(ty)}) scale(1.45) translate(${-tx} ${f1(-ty)})"><path d="M${tx} ${f1(ty - 15)}C${tx + 3} ${f1(ty - 7)} ${tx + 10} ${f1(ty - 2)} ${tx + 10} ${f1(ty + 5)}A10 10 0 0 1 ${tx - 10} ${f1(ty + 5)}C${tx - 10} ${f1(ty - 2)} ${tx - 3} ${f1(ty - 7)} ${tx} ${f1(ty - 15)}Z" fill="#7FE3FF" stroke="#FFFFFF" stroke-width="2.5" opacity="${clamp(ta).toFixed(2)}"/></g>`; }
    P.eyes.forEach((e, i) => {
      const sd = i ? 1 : -1, x = sd * EYX, y = EY, id = `${uid}e${i}`;
      const open = clamp(1 - e.arc) * clamp(1 - e.shut), ry = Math.max(.5, e.r * e.sy * (1 - .75 * clamp(e.arc + e.shut)));
      const lx = x + e.pdx + clamp(P.look.x, -1.3, 1.3) * 10, ly = y + e.pdy + clamp(P.look.y, -1.3, 1.3) * 8;
      if (style === 'pontinhos') {
        if (open > .02) out += `<ellipse cx="${f1(lx)}" cy="${f1(y + (ly - y) * .6)}" rx="26" ry="${f1(Math.max(.5, 26 * e.sy * (1 - .75 * clamp(e.arc + e.shut))))}" fill="${pal.sc}" opacity="${open.toFixed(2)}"/>`;
      } else if (open > .02) {
        const sh = eyeShape(x, y, e.r, ry, e, sd);
        out += `<clipPath id="${id}"><path d="${sh}"/></clipPath><g opacity="${open.toFixed(2)}"><path d="${sh}" fill="${pal.sc}"/><g clip-path="url(#${id})">`;
        out += `<circle cx="${f1(lx)}" cy="${f1(ly)}" r="${f1(e.pr)}" fill="${pal.pu}"/><circle cx="${f1(lx - e.pr * .36)}" cy="${f1(ly - e.pr * .4)}" r="${f1(e.pr * .3)}" fill="#FFFFFF"/>`;
        out += `</g></g>`;
      }
      if (e.arc > .02) out += `<path d="M${x - 32} ${y + 12}Q${x} ${y - 36} ${x + 32} ${y + 12}" stroke="${pal.sc}" stroke-width="17" stroke-linecap="round" fill="none" opacity="${clamp(e.arc).toFixed(2)}"/>`;
      if (e.shut > .02) out += `<path d="M${x - 28} ${y}Q${x} ${y + 24} ${x + 28} ${y}" stroke="${pal.sc}" stroke-width="14" stroke-linecap="round" fill="none" opacity="${clamp(e.shut).toFixed(2)}"/>`;
      if (false) { const tt = e.bt * -sd; out += `<path d="M${x - 26} ${f1(y - 56 - e.bl + tt)}Q${x} ${f1(y - 72 - e.bl)} ${x + 26} ${f1(y - 56 - e.bl - tt)}" stroke="${pal.br}" stroke-width="11" stroke-linecap="round" fill="none" opacity="${clamp(e.ba).toFixed(2)}"/>`; }
    });
    const m = P.mouth, ma = 0;
    if (ma > .02) {
      const y = m.dy, w = m.w, cx = m.dx;
      const d = m.open > 1 ? `M${f1(cx - w)} ${f1(y)}Q${f1(cx)} ${f1(y + m.c)} ${f1(cx + w)} ${f1(y)}Q${f1(cx)} ${f1(y + m.c + m.open)} ${f1(cx - w)} ${f1(y)}Z` : `M${f1(cx - w)} ${f1(y)}Q${f1(cx)} ${f1(y + m.c)} ${f1(cx + w)} ${f1(y)}`;
      out += `<path d="${d}" stroke="${pal.sc}" stroke-width="${m.open > 1 ? 8 : 12}" stroke-linecap="round" stroke-linejoin="round" fill="${m.open > 1 ? pal.sc : 'none'}" opacity="${ma.toFixed(2)}"/>`;
    }
    out += `</g></g>`;
    const ink = dark ? '#FFFFFF' : INK;
    P.decor.forEach(d => {
      if (d.a < .01) return;
      const op = clamp(d.a).toFixed(2);
      if (d.type === 'svg') out += '<g opacity="' + op + '">' + d.svg.replace(/\{(\w+)\}/g, (m, k) => pal[k] || m) + '</g>';
      else if (d.type === 'badge') out += `<circle cx="${f1(d.x * 100)}" cy="${f1(d.y * 100)}" r="${f1(d.r * 100 + 7)}" fill="${paper}" opacity="${op}"/><circle cx="${f1(d.x * 100)}" cy="${f1(d.y * 100)}" r="${f1(d.r * 100)}" fill="#FB5423" opacity="${op}"/>`;
      else if (d.type === 'arc') { const R = d.r * 100, a0 = d.a0, a1 = d.a1, p = a => `${f1(d.x * 100 + Math.cos(a) * R)} ${f1(d.y * 100 + Math.sin(a) * R)}`; out += `<path d="M${p(a0)} A${f1(R)} ${f1(R)} 0 0 1 ${p(a1)}" fill="none" stroke="${pal[d.c]}" stroke-width="${f1(d.w)}" stroke-linecap="round" opacity="${op}"/>`; }
      else if (d.type === 'bit') out += d.sq ? `<rect x="${f1(d.x * 100 - d.r * 100)}" y="${f1(d.y * 100 - d.r * 100)}" width="${f1(d.r * 200)}" height="${f1(d.r * 200)}" rx="${f1(d.r * 45)}" fill="${pal[d.c]}" opacity="${op}" transform="rotate(${f1(d.rot || 0)} ${f1(d.x * 100)} ${f1(d.y * 100)})"/>` : `<circle cx="${f1(d.x * 100)}" cy="${f1(d.y * 100)}" r="${f1(d.r * 100)}" fill="${pal[d.c]}" opacity="${op}"/>`;
      else if (d.type === 'dot') out += `<circle cx="${f1(d.x * 100)}" cy="${f1(d.y * 100)}" r="${f1(d.r * 100)}" fill="${pal.bl}" opacity="${op}"/>`;
      else if (d.type === 'text') out += `<text x="${f1(d.x * 100)}" y="${f1(d.y * 100)}" font-family="Open Sans, Arial, sans-serif" font-weight="800" font-size="${f1(d.s * 100)}" text-anchor="middle" dominant-baseline="central" fill="${ink}" opacity="${op}">${d.txt}</text>`;
      else if (d.type === 'human' && d.r > .01) {
        const hr = d.r * 100, hx = d.x * 100, hy = d.y * 100, hc = dark ? '#8A8F98' : '#5F6368';
        out += `<g opacity="${op}"><circle cx="${f1(hx)}" cy="${f1(hy)}" r="${f1(hr)}" fill="${hc}"/>`;
        [-1, 1].forEach(sd => { out += `<circle cx="${f1(hx + sd * hr * .3 - hr * .12)}" cy="${f1(hy - hr * .12)}" r="${f1(hr * .11)}" fill="#FFFFFF"/>`; });
        out += `</g>`;
      }
    });
    return out + `</svg>`;
  }
  const toDataUri = svg => 'data:image/svg+xml,' + encodeURIComponent(svg).replace(/'/g, '%27').replace(/\(/g, '%28').replace(/\)/g, '%29');
  const T3 = TAU / 3, eo = t => easeOut(t), L3 = f => [0, 1, 2].map(f);
  const NV = (function () {
    const f1 = v => Math.round(v * 10) / 10, sm = u => u * u * (3 - 2 * u), cl = u => Math.max(0, Math.min(1, u));
    const line = (x1, y1, x2, y2, col, w, op) => '<line x1="' + f1(x1) + '" y1="' + f1(y1) + '" x2="' + f1(x2) + '" y2="' + f1(y2) + '" stroke="' + col + '" stroke-width="' + w + '" stroke-linecap="round" opacity="' + op + '"/>';
    const brackets = (x, y, b, k, col, w, op) => { let d = ''; [[-1, -1], [1, -1], [1, 1], [-1, 1]].forEach(([sx, sy]) => { const X = x + sx * b, Y = y + sy * b; d += 'M' + f1(X - sx * k) + ' ' + f1(Y) + 'L' + f1(X) + ' ' + f1(Y) + 'L' + f1(X) + ' ' + f1(Y - sy * k); }); return '<path d="' + d + '" fill="none" stroke="' + col + '" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round" opacity="' + f1(op) + '"/>'; };
    const cyc = (t, P) => { const q = ((t % P) + P) % P / P, zin = sm(cl((q - .48) / .14)), zout = sm(cl((q - .86) / .12)); return { q, z: zin * (1 - zout), lock: cl((q - .64) / .05) * (1 - cl((q - .84) / .04)) }; };
    const pupil = (t, c, R) => { const sx = Math.sin(t * 2.3) * R * .42, sy = Math.sin(t * 4.6) * R * .12; return { px: sx + (R * .22 - sx) * c.z, py: sy + (-R * .14 - sy) * c.z, pr: 6 + 5 * c.z }; };
    const glass = (cx, cy, R, t, c, o, clipH) => { let s = '<circle cx="' + f1(cx) + '" cy="' + f1(cy) + '" r="' + f1(R) + '" fill="#0A0F1E"/><circle cx="' + f1(cx) + '" cy="' + f1(cy) + '" r="' + f1(R * .92) + '" fill="{wv}" opacity=".16"/><circle cx="' + f1(cx) + '" cy="' + f1(cy) + '" r="' + f1(R * .5) + '" fill="{wv}" opacity=".12"/>';
      for (let y = -R + 5; y < R; y += 6) { const hw = Math.sqrt(R * R - y * y) * .96; s += line(cx - hw, cy + y, cx + hw, cy + y, '{wv}', 1.2, .12); }
      const yy = -R + 2 * R * ((t * .8) % 1), shw = Math.sqrt(Math.max(0, R * R - yy * yy)); s += line(cx - shw, cy + yy, cx + shw, cy + yy, '{wv}', 2, .55);
      const g = R * .2; s += line(cx - R * .8, cy, cx - g, cy, '{wv}', 1.4, .5) + line(cx + g, cy, cx + R * .8, cy, '{wv}', 1.4, .5) + line(cx, cy - R * .8, cx, cy - g, '{wv}', 1.4, .5) + line(cx, cy + g, cx, cy + R * .8, '{wv}', 1.4, .5);
      for (let i = 0; i < 36; i++) { const a = i / 36 * Math.PI * 2 + o.rot, r1 = R - 3, r2 = R - (i % 3 ? 7 : 12); s += line(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1, cx + Math.cos(a) * r2, cy + Math.sin(a) * r2, '{wv}', 1.4, .7); }
      const px = cx + o.px, py = cy + o.py; s += '<circle cx="' + f1(px) + '" cy="' + f1(py) + '" r="' + f1(o.pr * 2.1) + '" fill="{wv}" opacity=".3"/><circle cx="' + f1(px) + '" cy="' + f1(py) + '" r="' + f1(o.pr) + '" fill="#FFFFFF"/>';
      if (c.lock > .01) s += brackets(px, py, o.pr * 2.4 + 12 * (1 - c.lock), o.pr * 1.1, '{ch}', 3, c.lock);
      return s; };
    const housing = (cx, cy, R) => '<circle cx="' + f1(cx) + '" cy="' + f1(cy) + '" r="' + f1(R + 9) + '" fill="#161A2E"/><circle cx="' + f1(cx) + '" cy="' + f1(cy) + '" r="' + f1(R + 9) + '" fill="none" stroke="{bl}" stroke-width="4"/>';
    const readout = (x, y, z, lock) => '<rect x="' + f1(x - 26) + '" y="' + f1(y - 11) + '" width="52" height="22" rx="11" fill="#161A2E"/><text x="' + f1(x) + '" y="' + f1(y + 4.5) + '" text-anchor="middle" font-family="Geist, Open Sans, sans-serif" font-weight="600" font-size="13" fill="' + (lock > .5 ? '#FFB08F' : '#FFFFFF') + '">' + (1 + 3 * z).toFixed(1) + '×</text>';
    return { f1, sm, cl, line, brackets, cyc, pupil, glass, housing, readout };
  })();
  const HAT = (hy, tilt) => { const f1 = NV.f1; return '<g transform="rotate(' + f1(tilt) + ' 0 ' + f1(hy) + ')"><ellipse cx="0" cy="' + f1(hy) + '" rx="84" ry="15" fill="#161A2E"/><path d="M-50 ' + f1(hy - 2) + ' C-52 ' + f1(hy - 40) + ' -34 ' + f1(hy - 62) + ' 0 ' + f1(hy - 58) + ' C34 ' + f1(hy - 62) + ' 52 ' + f1(hy - 40) + ' 50 ' + f1(hy - 2) + ' Z" fill="#161A2E"/><path d="M-16 ' + f1(hy - 58) + ' Q0 ' + f1(hy - 44) + ' 16 ' + f1(hy - 58) + '" fill="none" stroke="#2A2F4A" stroke-width="4" stroke-linecap="round"/><path d="M-50 ' + f1(hy - 16) + ' L50 ' + f1(hy - 16) + ' L50 ' + f1(hy - 4) + ' L-50 ' + f1(hy - 4) + ' Z" fill="{ch}"/></g>'; };
  const EYEW = (x, y, r, px, py, lid) => { const f1 = NV.f1; return '<circle cx="' + f1(x) + '" cy="' + f1(y) + '" r="' + f1(r) + '" fill="#FFFFFF"/><circle cx="' + f1(x + px * r * .35) + '" cy="' + f1(y + py * r * .35) + '" r="' + f1(r * .5) + '" fill="#161A2E"/><circle cx="' + f1(x + px * r * .35 - r * .18) + '" cy="' + f1(y + py * r * .35 - r * .18) + '" r="' + f1(r * .16) + '" fill="#FFFFFF"/>' + (lid > .01 ? '<path d="M' + f1(x - r - 2) + ' ' + f1(y - r - 2) + ' L' + f1(x + r + 2) + ' ' + f1(y - r - 2) + ' L' + f1(x + r + 2) + ' ' + f1(y - r + 2 * r * lid) + ' L' + f1(x - r - 2) + ' ' + f1(y - r + 2 * r * lid - 6) + ' Z" fill="{bl}"/>' : ''); };
  const HID = (a, b) => { const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2; return mx * mx + my * my < 100 * 100; };
  const XC = ['#E0685E', '#E776A6', '#A56BE0', '#4FC3D9', '#D8C95A'];
  const SEG = (pts, col, w0, w1, op0, opf) => { const f1 = NV.f1; let s = ''; const n = pts.length - 1; for (let j = 0; j < n; j++) { const a = pts[j], b = pts[j + 1], tp = 1 - j / n, op = op0 * tp * (opf ? opf(a, b) : 1); if (op < .02) continue; s += '<line x1="' + f1(a[0]) + '" y1="' + f1(a[1]) + '" x2="' + f1(b[0]) + '" y2="' + f1(b[1]) + '" stroke="' + col + '" stroke-width="' + f1(w1 + (w0 - w1) * tp) + '" stroke-linecap="round" opacity="' + f1(op) + '"/>'; } return s; };
  const OV = {
    listening: [t => { const p = i => Math.pow(Math.max(0, Math.sin(t * Math.PI * 2 - i * .9)), 4); return { roll: -4, twist: -3, drift: 0, lay: L3(i => ({ s: 1 + .04 * p(i), x: -5 * p(i) * (i + 1), y: 4 * p(i) * (i + 1) })), look: { x: -.6, y: .8 } }; }, 'Inclina na direção do campo e as camadas se esticam para ele, uma depois da outra, a cada tecla que você digita. É ele recebendo o que você escreve.'],
    writing: [t => { const b = i => 46 * Math.max(0, Math.sin(t * 6.5 - i * 1.15)); const X = [-150, 150, 0]; return { roll: 0, sy: 1, sx: 1, y: 0, twist: t * 30, lay: L3(i => ({ m: 1, x: X[i], y: 40 - b(i === 2 ? 1 : i === 0 ? 0 : 2), s: .3 })), fo: { x: 0, y: 40 - b(1) + 14 }, eyeS: .34, look: { x: 0, y: 1 } }; }, 'Desmonta em três gotas, uma de cada cor, que pulsam como quem digita a resposta. Os olhos pulam na gota do meio.'],
    thinking: [t => { const a = t * 2.4, sat = k => { const q = a + k * Math.PI, z = Math.sin(q); return { m: 1, x: Math.cos(q) * 285, y: -30 + z * 70, s: .34 + .1 * z }; }; const fx = Math.cos(a), fz = Math.sin(a), front = fz > 0 ? fx : -fx; return { r: .95, twist: t * 90, wob: 1.25, lay: [sat(0), sat(1), { m: 0, s: .7 + .02 * Math.sin(t * 3) }], eyeS: .74, look: { x: front * 1.1, y: -.9 }, roll: 8, drift: 0 }; }, 'A camada azul fica como cabeça e as outras duas orbitam em volta dela, uma de cada lado. Os olhos seguem a que passa na frente, como quem procura a resposta.'],
    searching: [t => { const g = NV.sm(NV.cl(t / .7)), tilt = -16 * Math.PI / 180, ct = Math.cos(tilt), st = Math.sin(tilt), R = 158, ry = .34; let back = '', front = ''; for (let k = 0; k < 5; k++) { const ph = k * 1.2566, u0 = t * 3.1 + ph, L = 2.6, n = 40, pts = []; for (let j = 0; j <= n; j++) { const u = u0 - L * j / n, w = Math.sin(3 * u + k * 1.3 + t * 1.5), x = (R + 9 * w) * Math.cos(u), y = (R + 9 * w) * Math.sin(u) * ry + 8 * Math.cos(3 * u + k); pts.push([x * ct - y * st, x * st + y * ct, Math.sin(u)]); } for (let j = 0; j < n; j++) { const a = pts[j], b = pts[j + 1], seg = SEG([a, b], XC[k], 5 - 4 * j / n, 5 - 4 * (j + 1) / n, (1 - j / n) * g, null); if ((a[2] + b[2]) > 0) front += seg; else if (!HID(a, b)) back += seg.replace(/opacity="([\d.]+)"/, (m, o) => 'opacity="' + NV.f1(o * .35) + '"'); } } return { r: .8, x: 0, y: 0, roll: 0, drift: 0, twist: t * 14, eyeA: 1, lay: [{}, {}, {}], look: { x: .5 * Math.cos(t * 3.1), y: .1 }, decor: [{ type: 'svg', svg: back + front, a: 1 }] }; }, 'Um anel de fios coloridos, que não são dele, gira rápido em volta como um cinturão, com os cinco fios entrelaçados no mesmo caminho. Na frente eles ficam fortes, atrás ficam claros. Organizado, redondo e contínuo, como conhecimento de fora circulando em volta dele.'],
    searching2: [t => { const g = NV.sm(NV.cl(t / .6)), P = 1.8; let s = '', hit = 0; for (let k = 0; k < 5; k++) { const q = ((t / P - k / 5) % 1 + 1) % 1, a0 = k * 1.2566 + .4, pos = p => { const r = 178 - 86 * p, a = a0 + 2.8 * p; return [Math.cos(a) * r, Math.sin(a) * r]; }, n = 26, tl = .4, pts = []; for (let j = 0; j <= n; j++) { const p = q - tl * j / n; if (p < 0) break; pts.push(pos(p)); } const fin = NV.sm(NV.cl((q - .9) / .1)); s += SEG(pts, XC[k], 5, 1, g * (1 - fin), null); if (pts.length) { const hd = pts[0]; s += '<circle cx="' + NV.f1(hd[0]) + '" cy="' + NV.f1(hd[1]) + '" r="5" fill="' + XC[k] + '" opacity="' + NV.f1(g * (1 - fin)) + '"/>'; } hit = Math.max(hit, Math.exp(-Math.pow((q - .97) / .03, 2))); } return { r: .8 * (1 + .05 * hit), x: 0, y: 0, roll: 0, drift: 0, twist: t * 16 + 30 * hit, eyeA: 1, lay: L3(i => ({ s: 1 + .04 * hit })), look: { x: .3 * Math.sin(t * 1.3), y: -.2 }, decor: [{ type: 'svg', svg: s, a: 1 }] }; }, 'Fios de conhecimento chegam de fora em espiral, um de cada cor, e entram nele. Cada vez que um fio chega, o corpo pulsa e as camadas dão um giro, como quem absorve a informação.'],
    searching3: [t => { const f1 = NV.f1, g = NV.sm(NV.cl(t / .6)), N = 40, R = 152, A = t * 3.2, TAU2 = Math.PI * 2; let s = ''; for (let i = 0; i < N; i++) { const a = i / N * TAU2 - Math.PI / 2, d = (((A - a) % TAU2) + TAU2) % TAU2, lit = Math.exp(-d / .9), c = XC[i % 5]; s += '<circle cx="' + f1(Math.cos(a) * R) + '" cy="' + f1(Math.sin(a) * R) + '" r="' + f1(2.6 + 3.6 * lit) + '" fill="' + c + '" opacity="' + f1((.2 + .8 * lit) * g) + '"/>'; } const P = .9, q = (t % P) / P, k = Math.floor(t / P), fa = (A - q * P * 3.2), fl = 1 - q, c = XC[(k * 3) % 5]; const x1 = Math.cos(fa) * (R - 8), y1 = Math.sin(fa) * (R - 8), x2 = Math.cos(fa) * 98, y2 = Math.sin(fa) * 98, m = NV.sm(NV.cl(q / .35)); s += '<line x1="' + f1(x1) + '" y1="' + f1(y1) + '" x2="' + f1(x1 + (x2 - x1) * m) + '" y2="' + f1(y1 + (y2 - y1) * m) + '" stroke="' + c + '" stroke-width="3" stroke-linecap="round" opacity="' + f1(fl * g) + '"/>'; return { r: .8, x: 0, y: 0, roll: 0, drift: 0, twist: t * 10, eyeA: 1, lay: [{}, {}, {}], look: { x: Math.cos(A) * .8, y: Math.sin(A) * .7 }, decor: [{ type: 'svg', svg: s, a: 1 }] }; }, 'Um círculo de pontos de informação, em cores de fora, envolve ele. Uma varredura gira acendendo os pontos um por um, e de tempos em tempos um ponto lança um fio até ele, como uma fonte respondendo. Os olhos acompanham a varredura.'],
    searching4: [t => { const f1 = NV.f1, g = NV.sm(NV.cl(t / .6)), tilt = -14 * Math.PI / 180, ct = Math.cos(tilt), st = Math.sin(tilt), RX = 172, RY = 46, N = 15; let back = '', front = ''; for (let i = 0; i < N; i++) { const u0 = t * 2.4 + i / N * Math.PI * 2, pts = []; for (let j = 0; j <= 4; j++) { const u = u0 - .16 * j / 4, x = RX * Math.cos(u), y = RY * Math.sin(u); pts.push([x * ct - y * st, x * st + y * ct]); } const fr = Math.sin(u0) > 0, seg = SEG(pts, XC[i % 5], fr ? 7 : 4.5, fr ? 5 : 3, (fr ? 1 : .35) * g, null); if (fr) front += seg; else if (!HID(pts[0], pts[4])) back += seg; } const rim = ''; return { r: .8, x: 0, y: .01 * Math.sin(t * 1.6), roll: -4, drift: 0, twist: t * 12, eyeA: 1, lay: [{}, {}, {}], look: { x: .6 * Math.cos(t * 2.4), y: .15 }, decor: [{ type: 'svg', svg: rim + back + front, a: 1 }] }; }, 'Um anel inclinado, como o de Saturno, gira rápido em volta dele carregando pedaços de informação coloridos. Os da frente passam fortes e grandes, os de trás pequenos e claros. Os olhos acompanham quem passa na frente.'],
    speaking: [t => { const C = ['ch', 'wv', 'bl'], N = 16, LIFE = .95, W = 5.2, bits = [], env = t2 => .5 + .5 * Math.pow(Math.abs(Math.sin(t2 * 1.25)), .6); for (let i = 0; i < N; i++) { const q = ((t / LIFE - i / N) % 1 + 1) % 1, born = t - q * LIFE, e = 1 - Math.pow(1 - q, 2.2), th = born * W + i * 2.39996, ang = th + 1.1 * e, rr = .98 + .56 * e, fo = Math.max(0, Math.min(1, (q - .4) / .6)); bits.push({ type: 'bit', c: C[i % 3], sq: i % 4 === 1, rot: ang * 57.3, x: Math.cos(ang) * rr, y: Math.sin(ang) * rr * .96, r: (.062 - .042 * e) * (i % 3 === 1 ? .75 : 1), a: env(born) * Math.min(1, q * 10) * (1 - fo * fo * (3 - 2 * fo)) }); } const sp = t * W * 57.3 * .55 + 40 * Math.sin(t * 1.25); return { twist: sp, wob: 1.4, spread: .05 + .03 * Math.abs(Math.sin(t * 1.25)), drift: 0, roll: 0, sx: 1, sy: 1, lay: [{}, {}, {}], look: { x: 0, y: 0 }, decor: bits }; }, 'Vira um motor: o rosto fica calmo e de frente enquanto as três camadas giram rápido, cada uma para um lado. Da borda saem faíscas nas cores da marca, lançadas pela rotação em espiral, mais fortes a cada frase, como inteligência sendo gerada.'],
    handoff: [t => { const sm = u => u * u * (3 - 2 * u), g = sm(Math.min(1, t / .6)), P = 1.9, fly = (k, hgt) => { const q = ((t / P - k * .5) % 1 + 1) % 1, e = easeInOut(Math.min(1, q / .8)) * g, fi = sm(Math.min(1, q / .12)), fo = sm(Math.max(0, Math.min(1, (q - .7) / .18))); return { m: 0, x: 430 * e, y: -hgt * Math.sin(Math.PI * e), s: (1 - .7 * e) * (.5 + .5 * fi), a: fi * (1 - fo) }; }; const push = k => { const q = ((t / P - k * .5) % 1 + 1) % 1; return Math.exp(-Math.pow((q - .06) / .07, 2)); }, kick = Math.max(push(0), push(1)), n = Math.pow(Math.max(0, Math.sin(t * 2.6)), 6) * g; return { lay: [fly(0, 150), fly(1, -90), { s: 1 + .06 * kick + .025 * Math.sin(t * 3.1), x: 14 * kick, y: -6 * kick }], twist: 30 * Math.sin(t * 2) + 12 * kick, wob: 1.3, look: { x: 1, y: -.2 + .25 * n }, y: .02 * n }; }, 'A camada azul fica com ele, com os olhos, e continua viva: respira e dá um impulso para a frente cada vez que lança uma camada. A laranja e a ciano saem dela, uma de cada vez, por cima e por baixo, chegam até o atendente e somem. Depois renascem e partem de novo.'],
    success: [t => { const e = Math.sin(Math.PI * clamp((t - .75) / 1.1)); return { lay: L3(i => ({ x: Math.cos(i * T3 - Math.PI / 2) * 150 * e, y: Math.sin(i * T3 - Math.PI / 2) * 150 * e, s: 1 - .3 * e })) }; }, 'Pula e, ao aterrissar, as três camadas se abrem como uma flor e voltam ao lugar.'],
    success2: [t => { const f1 = NV.f1, sm = NV.sm, cl = NV.cl, P = 2.6, q = (t % P) / P, c = sm(cl((q - .12) / .22)), fo = 1 - sm(cl((q - .84) / .12)), b = Math.sin(Math.PI * cl((q - .3) / .16)); let s = '<path d="M-30 30 L-8 50 L34 10" fill="none" stroke="#FFFFFF" stroke-width="10" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="97" stroke-dashoffset="' + f1(97 * (1 - c)) + '" opacity="' + f1(fo) + '"/>'; ['{ch}', '{wv}', '{bl}'].forEach((col, i) => { const e = sm(cl((q - .32 - i * .08) / .45)); if (e > 0 && e < 1) s += '<circle cx="0" cy="0" r="' + f1(96 + 70 * e) + '" fill="none" stroke="' + col + '" stroke-width="' + f1(7 * (1 - e) + .5) + '" opacity="' + f1(1 - e) + '"/>'; }); return { r: 1, x: 0, y: -.03 * b, roll: 0, drift: 0, twist: 20 * b, sx: 1 + .05 * b, sy: 1 - .04 * b, lay: L3(i => ({ s: 1 + .06 * Math.sin(Math.PI * cl((q - .32 - i * .08) / .2)) })), decor: [{ type: 'svg', svg: s, a: 1 }] }; }, 'Um check branco se desenha no lugar da boca, com os olhos felizes. Quando ele fecha, as três camadas pulsam uma depois da outra e soltam três ondas nas cores da marca, como um carimbo de resolvido.'],
    success3: [t => { const f1 = NV.f1, sm = NV.sm, cl = NV.cl, P = 2.4, q = (t % P) / P, crouch = Math.sin(Math.PI * cl(q / .12)), pop = Math.sin(Math.PI * cl((q - .1) / .22)), tt = Math.max(0, (q - .12) * P), fo = 1 - sm(cl((q - .78) / .2)), C = ['{ch}', '{wv}', '{bl}']; let s = ''; if (q > .12) for (let i = 0; i < 18; i++) { const a = -Math.PI / 2 + (i / 17 - .5) * 2.4, v = 170 + 70 * ((i * 7) % 5) / 4, x = Math.cos(a) * v * tt * .9, y = -70 + Math.sin(a) * v * tt + .5 * 300 * tt * tt, rot = (i * 40 + tt * 520 * (i % 2 ? 1 : -1)), sz = 6 + (i % 3) * 2, col = C[i % 3]; s += i % 2 ? '<rect x="' + f1(x - sz / 2) + '" y="' + f1(y - sz / 2) + '" width="' + f1(sz) + '" height="' + f1(sz) + '" rx="2" fill="' + col + '" opacity="' + f1(fo) + '" transform="rotate(' + f1(rot) + ' ' + f1(x) + ' ' + f1(y) + ')"/>' : '<circle cx="' + f1(x) + '" cy="' + f1(y) + '" r="' + f1(sz * .55) + '" fill="' + col + '" opacity="' + f1(fo) + '"/>'; } return { r: 1, x: 0, y: .05 * crouch - .12 * pop, roll: 0, drift: 0, twist: 180 * sm(cl((q - .1) / .3)), sx: 1 + .08 * crouch - .05 * pop, sy: 1 - .1 * crouch + .08 * pop, lay: L3(i => ({ y: -30 * Math.sin(Math.PI * cl((q - .12 - i * .04) / .25)) })), decor: [{ type: 'svg', svg: s, a: 1 }] }; }, 'Agacha, pula e solta um estouro de confete saindo do próprio corpo, em pedacinhos nas cores das camadas, que caem com gravidade enquanto as camadas pulam em cascata.'],
    success4: [t => { const f1 = NV.f1, sm = NV.sm, cl = NV.cl, P = 2.8, q = (t % P) / P, sp = cl(q / .45), ang = 540 * (1 - Math.pow(1 - sp, 3)) + 22 * Math.sin(Math.PI * cl((q - .45) / .18)) * (1 - cl((q - .63) / .1)), star = (x, y, k, d) => { const e = Math.sin(Math.PI * cl((q - d) / .28)); if (e <= 0) return ''; const r = k * e, w = r * .28; return '<path d="M' + f1(x) + ' ' + f1(y - r) + ' Q' + f1(x + w) + ' ' + f1(y - w) + ' ' + f1(x + r) + ' ' + f1(y) + ' Q' + f1(x + w) + ' ' + f1(y + w) + ' ' + f1(x) + ' ' + f1(y + r) + ' Q' + f1(x - w) + ' ' + f1(y + w) + ' ' + f1(x - r) + ' ' + f1(y) + ' Q' + f1(x - w) + ' ' + f1(y - w) + ' ' + f1(x) + ' ' + f1(y - r) + ' Z" fill="{ch}"/>'; }; const snap = Math.sin(Math.PI * cl((q - .44) / .14)); return { r: 1, x: 0, y: 0, roll: 0, drift: 0, wob: 1.2, twist: ang, sx: 1 + .04 * snap, sy: 1 + .04 * snap, lay: L3(i => ({ x: 0, y: 0, s: [1.14, 1.0, .86][i] * (1 + .03 * snap) })), decor: [{ type: 'svg', svg: star(96, -92, 26, .46) + star(-104, -54, 15, .54) + star(92, 70, 12, .6), a: 1 }] }; }, 'As três camadas se alinham como um selo e giram rápido, cada vez mais devagar, até travar com um tranquinho. Nesse momento brilham três estrelinhas em volta, e ele fica com os olhos felizes, como um selo de aprovado.'],
    notify: [t => ({ lay: L3(i => ({ y: -70 * Math.max(0, kick(t - i * .09, 2.2, 4)) })) }), 'As camadas pulam uma depois da outra, em cascata, e o badge nasce em cima.'],
    error: [t => { const sh = i => t > .1 ? Math.sin(TAU * 3.6 * (t - .1) - i * .7) * Math.exp(-2.6 * (t - .1)) : 0; return { lay: L3(i => ({ x: 60 * sh(i) })) }; }, 'Cada camada balança fora de fase, como se tivesse perdido o encaixe, até assentar.'],
    offline: [() => ({ lay: L3(i => ({ y: 40 * (i - 1), s: .92 - .06 * i, a: i === 2 ? 1 : .5 })) }), 'As camadas se desalinham e desbotam, sobra só a da frente com cor.'],
    welcome: [t => { const k = i => clamp((t - .05 - i * .12) / .75), e = i => { const x = k(i), c1 = 1.4; return 1 + (c1 + 1) * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); }; return { lay: L3(i => ({ s: Math.max(.001, e(i)), u: Math.max(.001, e(1)), rot: (1 - k(i)) * (i - 1) * 80 })) }; }, 'As três camadas chegam uma de cada vez, girando para o lugar. Os olhos abrem por último e ele dá uma piscadela.'],
    goodbye: [t => { const sm = NV.sm, cl = NV.cl, P = 3.2, q = (t % P) / P, wk = cl((q - .2) / .025) * (1 - cl((q - .4) / .025)), nod = Math.sin(Math.PI * cl((q - .46) / .22)), hop = Math.sin(Math.PI * cl((q - .7) / .14)), pk = i => Math.sin(Math.PI * cl((q - .7 - i * .05) / .16)); return { r: 1, eyeA: 1, x: 0, mouth: MO({ rest: 1 }), roll: 4 * wk - 3 * nod, twist: 0, drift: 0, eyes: pair({}, { arc: wk }), blinkOK: 0, y: .05 * nod - .06 * hop, sy: 1 - .05 * nod + .04 * hop, sx: 1 + .03 * nod - .02 * hop, lay: L3(i => ({ x: 0, y: -14 * pk(i), s: 1 })), look: { x: .3 * wk, y: .6 * nod } }; }, 'Dá uma piscadela, acena com a cabeça como quem diz "até logo" e termina com um pulinho curto, com as camadas espiando para cima uma depois da outra. Depois fica ali em repouso, pronto para a próxima.'],
  };
  STATES.forEach(S => { const o = OV[S.id]; if (!o) return; const p0 = S.pose; S.pose = (t, X) => { const P = p0(t, X) || {}, q = o[0](t, X); for (const k in q) P[k] = q[k]; return P; }; S.moves = o[1]; });
  window.ActuarBot6 = { BODIES, PALETTES, PAL_BY, EYE_STYLES, EXPRESSIONS, EXPR_BY, STATES, STATE_BY, sample, poseAt, render, toDataUri, total, spring };
})();

// ---- driver (the blog hero) ----
(() => {
  const A = window.ActuarBot6, still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const big = document.getElementById('orb'), body = document.createElement('div');
  body.style.cssText = 'position:absolute;inset:0;transform-origin:50% 62%;will-change:transform'; big.appendChild(body);
  const sm = x => x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x);
  const env = (c, a, b, i = .3, o = .35) => sm((c - a) / i) * (1 - sm((c - (b - o)) / o));
  // a cada 6 s ele faz um gesto, alternando: (0) inclina a cabeça e dá uma piscadela; (1) sorri com os dois olhos e dá um pulinho
  const CY = 6, gest = s => { const c = s % CY; return { k: Math.floor(s / CY) % 2, c, g: env(c, 3.4, 5.1) }; };
  const exprAt = s => {
    const { k, g } = gest(s), E = JSON.parse(JSON.stringify(A.EXPR_BY.neutro)), w = sm(g * 1.3);
    if (k === 0) { E.eyes[1].arc = w; E.eyes[0].sy = 1 - .1 * w; } else { E.eyes[0].arc = E.eyes[1].arc = w; }
    return E;
  };
  const bodyAt = s => {
    const { k, g, c } = gest(s), sway = Math.sin(s * 1.05) * 1.4, bob = Math.sin(s * 2.1) * .5;
    if (k === 0) return `translateY(${(bob - 1.5 * g).toFixed(3)}%) rotate(${(sway - 10 * g).toFixed(2)}deg)`;
    const hop = Math.sin(sm((c - 3.5) / .55) * Math.PI) * 3.4, squash = Math.sin(sm((c - 3.35) / .2) * Math.PI) * .04;
    return `translateY(${(bob - hop).toFixed(3)}%) rotate(${(sway + 2.5 * g).toFixed(2)}deg) scale(${(1 + squash).toFixed(3)}, ${(1 - squash).toFixed(3)})`;
  };
  // olhar: título → você → título; no gesto, direto para você; com o mouse na tela, segue o cursor
  const idleLook = s => { const c = s % CY, y = sm((c - 1.3) / .45) * (1 - sm((c - 2.7) / .45)); return { x: -.6 * (1 - y), y: .06 }; };
  let ptr = { x: -.6, y: .06 }, mouse = null;
  addEventListener('pointermove', e => { const r = big.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2, k = r.width / 2.4;
    mouse = { x: Math.max(-1, Math.min(1, (e.clientX - cx) / k)), y: Math.max(-1, Math.min(1, (e.clientY - cy) / k)) }; });
  document.addEventListener('pointerleave', () => { mouse = null; });
  const draw = s => {
    const { g } = gest(s), base = mouse || idleLook(s), tgt = { x: base.x * (1 - g), y: base.y * (1 - g) + .04 * g };
    ptr = { x: ptr.x + (tgt.x - ptr.x) * .16, y: ptr.y + (tgt.y - ptr.y) * .16 };
    const P = A.sample(.6 + s, [{ state: 'idle', dur: 1e9 }], { expr: exprAt(s), energy: 1, follow: true, pointer: ptr, followW: 1 });
    body.innerHTML = A.render(P, { size: 960, body: 'orbe', eyes: 'pontinhos', pal: A.PAL_BY.oficial, bg: 'escuro', uid: 'big', noPaper: true });
    body.style.transform = bodyAt(s);
    const Q = A.sample(3.1 + s, [{ state: 'idle', dur: 1e9 }], { expr: A.EXPR_BY.neutro, energy: 1 });
    document.getElementById('lorb').innerHTML = A.render(Q, { size: 90, body: 'orbe', eyes: 'pontinhos', pal: A.PAL_BY.oficial, bg: 'escuro', uid: 'sm', noPaper: true });
  };
  if (still) { ptr = { x: -.6, y: .06 }; draw(0); return; }
  const t0 = performance.now(); let last = 0;
  const loop = now => { if (now - last > 30) { last = now; draw((now - t0) / 1000); } requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
})();
