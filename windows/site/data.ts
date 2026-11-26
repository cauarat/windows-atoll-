// What the island on the download page is fed: the settings of the MacBook it
// was modelled on, and sample messages, agents, music and meetings.
//
// Nothing here is anyone's real conversation. Names are made up, except
// `maria.eduarda`, which is the sender the app's own photo preview uses. The
// voice notes are macOS's own pt-BR voices reading the transcripts.

import type { Settings } from "../src/core/state";
import type { AgendaMeeting } from "../src/core/agendaRules";
import type { ClipEntry, MediaState, MessageEvent, MessageSource } from "../src/core/bridge";
// Every sample file, by name: media/photo-site.jpg is "photo-site".
const files = import.meta.glob("./media/*.{png,jpg,m4a}", { eager: true, query: "?url", import: "default" }) as Record<string, string>;

export const params = new URLSearchParams(location.search);
export type Scene = "hero" | "message" | "water" | "rest" | "greet";
export const SCENE = (params.get("scene") ?? "hero") as Scene;
type Lang = "en" | "pt-BR" | "es";
// The Mac this was modelled on speaks Brazilian Portuguese.
const asked = params.get("lang") ?? "pt-BR";
export const LANG: Lang = asked.startsWith("pt") ? "pt-BR" : asked.startsWith("es") ? "es" : "en";

// The characters each pill wears on that Mac (its pillCharacters, written the
// way the Windows build stores them: accessory:eye:shape:head.eyes.texture.extra).
export const MAC_CHARACTERS: Record<string, string> = {
  integration_mattermost: "beret:sleepy:fluffy:beanie.-.snowyPines.-",
  integration_whatsapp: "crown:glossy:boxy:antlers.jolly.-.snowfall",
  integration_music: "sprout:sleepy:heart:topHat.treeGlasses.-.-",
  integration_ato: "catEars:dot:pointy:holly.-.gingerbread.lights",
  integration_claude: "sparkles:glossy:round",
  integration_notifications: "catEars:dot:pointy:santaHat.jolly.-.beard",
};
export const MAC_DEFAULT_CHARACTER = "catEars:dot:pointy:santaHat.jolly.-.beard";

/** Settings changed in the demo's Settings window, shared by every island on the page. */
export const SAVED_KEY = "notchy-demo-settings";
export function savedSettings(): Partial<Settings> {
  try { return JSON.parse(sessionStorage.getItem(SAVED_KEY) ?? "{}"); } catch { return {}; }
}

export function demoSettings(): Partial<Settings> {
  const sticky = SCENE === "message" || SCENE === "water";
  const own: Partial<Settings> = {
    enabled: true,
    soundEnabled: true,
    soundVolume: 0.2,
    // The feature boxes hold their card a while; the hero folds after five
    // seconds, as the Mac does.
    autoCloseInterval: sticky ? 120 : 5,
    absenceInterval: 300,
    alwaysVisible: true,
    activeIntegrations: ["integration_mattermost", "integration_ato", "integration_music", "integration_whatsapp"],
    screen: "primary",
    position: "top-centre",
    homeContent: "claudeCode",
    language: LANG,
    pillCharacters: { ...MAC_CHARACTERS },
    defaultCharacter: MAC_DEFAULT_CHARACTER,
    hideCharacters: false,
    islandEdgeButtons: [
      { action: "integration_mattermost", side: "left" },
      { action: "integration_music", side: "right" },
      { action: "integration_notifications", side: "right" },
      { action: "integration_ato", side: "left" },
      { action: "integration_whatsapp", side: "left" },
      { action: "hydration", side: "bottom" },
      { action: "agenda", side: "bottom" },
    ] as Settings["islandEdgeButtons"],
    // The Chat tab opens ChatGPT's own page, as on that Mac.
    webChat: true,
    messageFullBody: true,
    islandSnow: true,
    // On, as on the Mac: the hero's greeting starts it. Elsewhere one player
    // is plenty.
    christmasMusic: SCENE === "hero",
    agendaEnabled: true,
    agendaLeadMinutes: 15,
    hooksInstalled: true,
    autoUpdate: false,
    onboardingVersion: 1,
    userName: "Cauã",
  };
  // What the visitor changed in Settings wins, except how long each box holds
  // its card, which is the page's business.
  const saved = savedSettings();
  delete saved.autoCloseInterval;
  delete saved.christmasMusic;
  return { ...own, ...saved };
}

// ── The inboxes ──────────────────────────────────────────────────────────────
// Each service "connected" in test mode: words, a photo and a voice note in
// each, already waiting when the island starts, and more arriving later.

export const MEDIA: Record<string, string> = Object.fromEntries(
  Object.entries(files).map(([path, url]) => [path.replace(/^.*\/|\.[a-z0-9]+$/g, ""), url]),
);

interface Sample {
  source: MessageSource;
  sender: string;
  text?: string;
  photo?: { file: string; w: number; h: number; caption: string; mime: string };
  voice?: { file: string; seconds: number; transcript: string };
}

let serial = 0;
export function toEvent(sample: Sample, minutesAgo = 0): MessageEvent {
  serial++;
  const id = `demo-${sample.source}-${serial}-${Date.now()}`;
  const ev: MessageEvent = {
    id, source: sample.source, kind: "directMessage", sender: sample.sender,
    channel: null, conversationId: `demo-${sample.source}-${sample.sender}`,
    body: sample.text ?? sample.photo?.caption ?? sample.voice?.transcript ?? "",
    timestampMs: Date.now() - minutesAgo * 60_000, link: "https://example.invalid/",
    // The words as sent, which Rust fills in the app: Copy is offered only
    // when there is something to copy.
    text: sample.text ?? sample.photo?.caption ?? null,
  };
  if (sample.photo) {
    ev.photo = {
      fileId: `${sample.photo.file}#${serial}`, name: sample.photo.file, mimeType: sample.photo.mime,
      pixelWidth: sample.photo.w, pixelHeight: sample.photo.h, hasPreview: false, byteCount: 120_000,
      miniPreview: null, caption: sample.photo.caption, more: 0,
    };
  }
  if (sample.voice) {
    ev.audio = {
      attachmentId: `a-${serial}`, storageFileId: `${sample.voice.file}#${serial}`,
      fileName: `${sample.voice.file}.m4a`, contentType: "audio/mp4",
      durationSeconds: sample.voice.seconds, transcriptStatus: "ready", transcript: sample.voice.transcript,
    };
  }
  return ev;
}

type Content = { inbox: [Sample, number][]; arriving: Sample[] };
const V = LANG === "pt-BR" ? "pt" : LANG;
const photo = (file: string, caption: string, w = 238, h = 238, mime = "image/png") => ({ file, w, h, caption, mime });
const voice = (name: string, seconds: number, transcript: string) => ({ file: `voice-${name}-${V}`, seconds, transcript });

const CONTENT: Record<"pt-BR" | "en" | "es", Content> = {
  "pt-BR": {
    inbox: [
      [{ source: "whatsapp", sender: "Bia", photo: photo("photo-wink", "kkkkk olha a cara dele") }, 64],
      [{ source: "ato", sender: "Box Ferro", photo: photo("photo-proud", "Olha a turma de hoje! 💪") }, 50],
      [{ source: "mattermost", sender: "maria.eduarda", photo: photo("photo-site", "olha o site novo do Notchy 👀", 1200, 750, "image/jpeg") }, 35],
      [{ source: "whatsapp", sender: "Lucas", voice: voice("wa", 3, "E aí, bora no futebol hoje às oito?") }, 27],
      [{ source: "ato", sender: "Studio Pulse", voice: voice("ato1", 7, "Oi, tudo bem? Queria saber se dá pra mudar o horário da minha aula de quinta pra sexta.") }, 22],
      [{ source: "mattermost", sender: "joao.pedro", voice: voice("mm", 5, "Oi! Subi o build novo no staging. Dá uma olhada quando puder?") }, 18],
      [{ source: "whatsapp", sender: "Mãe", text: "Vem jantar no domingo? 🍝" }, 9],
      [{ source: "ato", sender: "Academia Forma", text: "Oi! Pode me mandar o boleto deste mês?" }, 6],
      [{ source: "mattermost", sender: "ana.lima", text: "A design review foi pras 15h — ainda consegue ir?" }, 4],
    ],
    arriving: [
      { source: "mattermost", sender: "maria.eduarda", photo: photo("photo-love", "olha isso") },
      { source: "whatsapp", sender: "Mãe", text: "Chegou bem? Me avisa 😘" },
      { source: "ato", sender: "Studio Pulse", voice: voice("ato2", 5, "Bom dia! Já fiz o pagamento, vou te mandar o comprovante.") },
      { source: "mattermost", sender: "ana.lima", text: "Pode revisar meu PR quando sobrar um tempinho?" },
      { source: "whatsapp", sender: "Bia", photo: photo("photo-surprised", "você viu isso??") },
      { source: "ato", sender: "Academia Forma", text: "Obrigado! Recebi o boleto aqui 🙏" },
    ],
  },
  en: {
    inbox: [
      [{ source: "whatsapp", sender: "Bia", photo: photo("photo-wink", "lol look at his face") }, 64],
      [{ source: "ato", sender: "Box Ferro", photo: photo("photo-proud", "Today's class! 💪") }, 50],
      [{ source: "mattermost", sender: "maria.eduarda", photo: photo("photo-site", "look at Notchy's new site 👀", 1200, 750, "image/jpeg") }, 35],
      [{ source: "whatsapp", sender: "Lucas", voice: voice("wa", 2, "Hey, football tonight at eight?") }, 27],
      [{ source: "ato", sender: "Studio Pulse", voice: voice("ato1", 6, "Hi, how are you? I wanted to know if I can move my Thursday class to Friday.") }, 22],
      [{ source: "mattermost", sender: "joao.pedro", voice: voice("mm", 5, "Hey! I pushed the new build to staging. Can you take a look when you get a chance?") }, 18],
      [{ source: "whatsapp", sender: "Mom", text: "Are you coming for dinner on Sunday? 🍝" }, 9],
      [{ source: "ato", sender: "Academia Forma", text: "Hi! Could you send me this month's invoice?" }, 6],
      [{ source: "mattermost", sender: "ana.lima", text: "Design review moved to 3 pm — can you still make it?" }, 4],
    ],
    arriving: [
      { source: "mattermost", sender: "maria.eduarda", photo: photo("photo-love", "look at this") },
      { source: "whatsapp", sender: "Mom", text: "Did you get home ok? Let me know 😘" },
      { source: "ato", sender: "Studio Pulse", voice: voice("ato2", 4, "Good morning! I've already paid, I'll send you the receipt.") },
      { source: "mattermost", sender: "ana.lima", text: "Could you review my PR when you have a minute?" },
      { source: "whatsapp", sender: "Bia", photo: photo("photo-surprised", "did you see this??") },
      { source: "ato", sender: "Academia Forma", text: "Thanks! Got the invoice 🙏" },
    ],
  },
  es: {
    inbox: [
      [{ source: "whatsapp", sender: "Bia", photo: photo("photo-wink", "jajaja mira su cara") }, 64],
      [{ source: "ato", sender: "Box Ferro", photo: photo("photo-proud", "¡Mira la clase de hoy! 💪") }, 50],
      [{ source: "mattermost", sender: "maria.eduarda", photo: photo("photo-site", "mira la web nueva de Notchy 👀", 1200, 750, "image/jpeg") }, 35],
      [{ source: "whatsapp", sender: "Lucas", voice: voice("wa", 2, "Oye, ¿fútbol hoy a las ocho?") }, 27],
      [{ source: "ato", sender: "Studio Pulse", voice: voice("ato1", 5, "Hola, ¿qué tal? Quería saber si puedo cambiar mi clase del jueves al viernes.") }, 22],
      [{ source: "mattermost", sender: "joao.pedro", voice: voice("mm", 5, "¡Hola! Subí el build nuevo a staging. ¿Le echas un vistazo cuando puedas?") }, 18],
      [{ source: "whatsapp", sender: "Mamá", text: "¿Vienes a cenar el domingo? 🍝" }, 9],
      [{ source: "ato", sender: "Academia Forma", text: "¡Hola! ¿Me puedes enviar la factura de este mes?" }, 6],
      [{ source: "mattermost", sender: "ana.lima", text: "La design review pasó a las 15 h — ¿todavía puedes?" }, 4],
    ],
    arriving: [
      { source: "mattermost", sender: "maria.eduarda", photo: photo("photo-love", "mira esto") },
      { source: "whatsapp", sender: "Mamá", text: "¿Llegaste bien? Avísame 😘" },
      { source: "ato", sender: "Studio Pulse", voice: voice("ato2", 3, "¡Buenos días! Ya hice el pago, te mando el comprobante.") },
      { source: "mattermost", sender: "ana.lima", text: "¿Puedes revisar mi PR cuando tengas un rato?" },
      { source: "whatsapp", sender: "Bia", photo: photo("photo-surprised", "¿¿viste esto??") },
      { source: "ato", sender: "Academia Forma", text: "¡Gracias! Ya recibí la factura 🙏" },
    ],
  },
};

/** Waiting when the island starts, oldest first. */
export const INBOX = CONTENT[LANG].inbox;
/** Arriving while the visitor watches, one at a time, a different app each time. */
export const ARRIVING = CONTENT[LANG].arriving;

// ── Everything else the island asks for ─────────────────────────────────────
const STRINGS = {
  en: {
    prompt: "Make the download page feel like the app",
    stop: "Done — the page builds",
    chat: "I’m the website demo, so I can’t really answer. In Notchy your question goes to Claude, Gemini or ChatGPT, with your own key.",
    meetings: ["Weekly sync", "Design review", "Onboarding call"],
    clips: ["xattr -dr com.apple.quarantine /Applications/Notchy.app", "https://github.com/cauarat/windows-atoll-/releases", "look at this"],
  },
  "pt-BR": {
    prompt: "Deixa a página de download com a cara do app",
    stop: "Pronto — a página compila",
    chat: "Sou a demo do site, então não consigo responder de verdade. No Notchy a sua pergunta vai pro Claude, Gemini ou ChatGPT, com a sua própria chave.",
    meetings: ["Reunião semanal", "Design review", "Call de onboarding"],
    clips: ["xattr -dr com.apple.quarantine /Applications/Notchy.app", "https://github.com/cauarat/windows-atoll-/releases", "olha isso"],
  },
  es: {
    prompt: "Haz que la página de descarga se parezca a la app",
    stop: "Listo — la página compila",
    chat: "Soy la demo del sitio, así que no puedo responder de verdad. En Notchy tu pregunta va a Claude, Gemini o ChatGPT, con tu propia clave.",
    meetings: ["Reunión semanal", "Design review", "Llamada de onboarding"],
    clips: ["xattr -dr com.apple.quarantine /Applications/Notchy.app", "https://github.com/cauarat/windows-atoll-/releases", "mira esto"],
  },
} as const;
export const S = STRINGS[LANG];

export function meetings(nowMs = Date.now()): AgendaMeeting[] {
  const at = (m: number) => nowMs + m * 60_000;
  const meeting = (id: string, from: number, length: number, title: string, stageKey: string,
                   state = "open"): AgendaMeeting => ({
    attemptId: id, meetingId: `m-${id}`, caseId: `c-${id}`,
    department: stageKey === "contact" ? "backoffice" : "onboarding", stageKey,
    startMs: at(from), endMs: at(from + length), title, publicId: null, attemptSequence: 1,
    attemptState: "confirmed", meetingState: state,
  } as AgendaMeeting);
  return [
    meeting("d1", -95, 30, S.meetings[0], "contact", "attended"),
    meeting("d2", 22, 45, S.meetings[1], "connection"),
    meeting("d3", 150, 60, S.meetings[2], "connection_2"),
  ];
}

export function clipboard(): ClipEntry[] {
  const now = Date.now();
  return S.clips.map((body, i) => ({
    id: `clip-${i}`, kind: "text" as const, body, thumb: "", thumbW: 0, thumbH: 0,
    bytes: body.length, copiedAt: now - (i + 1) * 7 * 60_000, favourite: i === 0,
  }));
}

/** A cover drawn here, so no record label's artwork ships with the page. */
function cover(): string {
  const c = document.createElement("canvas");
  c.width = c.height = 240;
  const g = c.getContext("2d")!;
  const bg = g.createLinearGradient(0, 0, 240, 240);
  bg.addColorStop(0, "#2a1530");
  bg.addColorStop(1, "#12122a");
  g.fillStyle = bg;
  g.fillRect(0, 0, 240, 240);
  const glow = (x: number, y: number, r: number, color: string) => {
    const rg = g.createRadialGradient(x, y, 0, x, y, r);
    rg.addColorStop(0, color);
    rg.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = rg;
    g.fillRect(0, 0, 240, 240);
  };
  glow(70, 60, 140, "rgba(255,138,160,0.85)");
  glow(190, 200, 150, "rgba(109,93,246,0.8)");
  g.fillStyle = "rgba(255,255,255,0.9)";
  g.font = "600 22px -apple-system, BlinkMacSystemFont, Helvetica, sans-serif";
  g.fillText("Gymnopédies", 22, 206);
  return c.toDataURL("image/png");
}

/** What the feature boxes play: a piece old enough to belong to everyone. */
export function media(): MediaState {
  return {
    hasTrack: true, isPlaying: true, title: "Gymnopédie No. 1", artist: "Erik Satie",
    album: "Trois Gymnopédies", elapsed: 53, duration: 214, sourceName: "Music",
    sourceId: "com.apple.Music", artwork: cover(), rate: 1, sourceIcon: "",
  };
}
