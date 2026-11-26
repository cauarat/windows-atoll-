// Characters — the Mac's CharacterSettingsView, value for value.
//
// Two untitled GroupBoxes 12px apart, as the Mac's own VStack sets them. The
// first holds the switch that puts every face away. The second is the picker:
// whose face is being changed, the body row, the face grid, the two pickers,
// Christmas while it is on offer, and the ways back to the default.
//
// Who each pill is. The colour is not chosen here on purpose: it comes from the
// pill, so the Mattermost bot keeps Mattermost's colour whatever it wears and
// the pill border still matches the creature inside it. Ato is not a Mochi at
// all but Ato's own mascot, so the body, the faces and the two pickers have
// nothing to say to it. It is listed for the one thing it can wear,
// Christmas, and only while there is Christmas to pick or to take off.
//
// Everything is built once per render and repainted in place. A click redraws
// only the previews whose character changed, and the control that was used
// keeps the keyboard.

import "./characters.css";
import { INTEGRATION_AGENTS, type AgentTask } from "../../core/state";
import {
  ACCESSORIES, ACCESSORY_LABEL, CHARACTER_PRESETS, EYES, EYE_LABEL, FESTIVE_SLOTS, SHAPES,
  characterFromStorage, characterToStorage, hasFestive, isFestiveSeason, sameFace, withFestive,
  type FestiveSlot, type MochiAccessory, type MochiCharacter, type MochiEye, type MochiShape,
} from "../../mochi/character";
import { MOCHI_SHAPE_LABEL } from "../../mochi/shape";
import { atoPreview, characterPreview } from "../../mochi/preview";
import { festiveData } from "../../mochi/festive";
import { ATO_PILL } from "../../ato/view";
import { h } from "../../views/dom";
import { t } from "../../core/i18n";
import { save, settings, subscribe } from "../store";
import {
  checkbox, disable, divider, groupBox, hint, hugBoxes, inlineRow, popup, pushButton, stack,
  type PopupOption,
} from "../controls";

/** The preview sizes `CharacterTile` is given: 42 in the body row, 46 for the faces and Christmas. */
const BODY_SIZE = 42;
const FACE_SIZE = 46;

/** A tile's name is 9.5px; a Christmas name may shrink to 80 % of that before it is cut. */
const NAME_SIZE = 9.5;
const NAME_MIN_SCALE = 0.8;
/** What `.ch-tile.shrink > span` keeps clear on its two sides together, px. */
const NAME_PAD = 4;

/** The colour of the Mochi nobody in particular owns — the Mac's `currentColor` fallback. */
const DEFAULT_COLOR = "#F5F6F8";

/** Keeps the Christmas names fitted when the window is resized. One pane's worth at a time. */
let resizeWatch: ResizeObserver | null = null;

/** One tile of a grid, kept across repaints. */
interface Tile {
  el: HTMLButtonElement;
  /** The body's size in the preview; the canvas is this over 0.6. */
  size: number;
  /** A Christmas tile, drawn as Ato's orb while Ato is the one being edited. */
  festive: boolean;
  /** Who the preview shows, given the character being edited. */
  shows(c: MochiCharacter): MochiCharacter;
  /** Whether this is the tile marked as chosen. */
  chosen(c: MochiCharacter): boolean;
  /** What a click on it writes. */
  picks(c: MochiCharacter): MochiCharacter;
  /** What the canvas in it was drawn from, so an unchanged preview is left alone. */
  drawn: string;
}

type TileRules = Pick<Tile, "shows" | "chosen" | "picks">;

/** Whether Christmas is on offer today. Always in a dev build, so it can be worked on in July. */
function christmasOpen(): boolean {
  return import.meta.env.DEV || isFestiveSeason();
}

/** Whoever has `id` — a pill — or nobody, for the default. */
function pill(id: string): AgentTask | undefined {
  return id ? INTEGRATION_AGENTS.find((a) => a.id === id) : undefined;
}

/**
 * A section heading with the name of whoever it is editing. The picker that
 * chooses them sits at the top of a pane that scrolls, so by the grids it is
 * gone — and every tile clicked writes to whoever is still selected up there.
 */
function heading(title: string): { el: HTMLElement; set(who: string): void } {
  const name = h("span", { class: "ch-for" });
  const el = h("div", { class: "ch-heading" }, title, name);
  return { el, set: (who) => { name.textContent = t("  for %@", who); } };
}

/** LazyVGrid, with `columns` flexible columns. */
function grid(columns: number, tiles: Tile[]): HTMLElement {
  const el = h("div", { class: "ch-grid", style: `--columns:${columns}` });
  el.append(...tiles.map((tile) => tile.el));
  return el;
}

/** Shows or hides each of `els` — an inline display, which beats any class's own. */
function show(els: HTMLElement[], on: boolean): void {
  for (const el of els) el.style.display = on ? "" : "none";
}

/**
 * Shrinks each Christmas name that does not fit, to as little as 80 %, before
 * the ellipsis cuts it — the Mac's `minimumScaleFactor(0.8)`. Reads every
 * width first and writes after, so it costs one layout, not one a name.
 */
function fitNames(within: HTMLElement): void {
  const spans = [...within.querySelectorAll<HTMLElement>(".ch-tile.shrink > span")];
  for (const span of spans) span.style.fontSize = "";
  const sizes = spans.map((span) => {
    const box = span.clientWidth;
    const text = span.scrollWidth;
    if (box === 0 || text <= box) return null;
    // A pixel to spare: glyphs do not scale exactly with the font size.
    return NAME_SIZE * Math.max(NAME_MIN_SCALE, (box - NAME_PAD - 1) / (text - NAME_PAD));
  });
  spans.forEach((span, i) => {
    const size = sizes[i];
    if (size != null) span.style.fontSize = `${size.toFixed(2)}px`;
  });
}

/** The Characters pane. */
export function render(): Node[] {
  resizeWatch?.disconnect();

  // Whose face is on the bench: "" is the default, which covers every pill
  // with no character of its own — and Mochi itself when nobody in particular
  // is speaking. Kept for this render only, like the Mac's @State: coming back
  // to the pane, or the window redrawn in another language, starts on
  // everyone else again.
  let editing = "";

  const current = (): MochiCharacter =>
    characterFromStorage((editing ? settings.pillCharacters[editing] : undefined)
      ?? settings.defaultCharacter);

  function write(character: MochiCharacter) {
    const text = characterToStorage(character);
    if (editing) {
      settings.pillCharacters = { ...settings.pillCharacters, [editing]: text };
    } else {
      settings.defaultCharacter = text;
    }
    void save();
    paint();
  }

  /** Takes these pills' own faces away, so the default reaches them again. */
  function forget(ids: string[]) {
    const gone = new Set(ids);
    settings.pillCharacters = Object.fromEntries(
      Object.entries(settings.pillCharacters).filter(([id]) => !gone.has(id)));
    void save();
    paint();
  }

  function tile(name: string, size: number, festive: boolean, rules: TileRules): Tile {
    const side = `${(size / 0.6).toFixed(3)}px`;
    const el = h("button", {
      type: "button",
      class: festive ? "ch-tile shrink" : "ch-tile",
      style: `--preview:${side}`,
      "aria-pressed": "false",
    },
    // Stands in for the preview until the first paint draws it.
    h("canvas", { width: "0", height: "0", style: `width:${side};height:${side}` }),
    h("span", { text: name }));
    el.addEventListener("click", () => write(rules.picks(current())));
    return { el, size, festive, drawn: "", ...rules };
  }

  function paintTiles(tiles: Tile[], c: MochiCharacter, color: string, ato: boolean) {
    for (const one of tiles) {
      const shown = one.shows(c);
      const orb = ato && one.festive;
      const key = `${orb ? "ato" : color}|${characterToStorage(shown)}`;
      if (key !== one.drawn) {
        one.el.firstElementChild?.replaceWith(orb
          ? atoPreview(shown.festive, one.size)
          : characterPreview(shown, color, one.size));
        one.drawn = key;
      }
      const on = one.chosen(c);
      one.el.classList.toggle("on", on);
      one.el.setAttribute("aria-pressed", String(on));
    }
  }

  // ── The switch ──────────────────────────────────────────────────────────────
  //
  // Above the picker because it is the question that comes first: whether
  // there is a character at all, before whose and which.

  const hide = checkbox(t("Hide the characters"), settings.hideCharacters, (on) => {
    settings.hideCharacters = on;
    void save();
    dim();
  });

  const offSwitch = groupBox({ title: null, gap: 10 },
    hide,
    // The Mac sentence ends on "the notch"; a PC has none, and the file is
    // dropped on the island.
    hint(t("Mochi and the little ones stop appearing, and every card closes the gap it was "
      + "leaving for a face. Nothing else changes: the player, your messages, the timer and "
      + "the pills all carry on. He still rides the compact bar, and still comes out to catch "
      + "a file you drop on the island.")),
  );

  // ── The picker ──────────────────────────────────────────────────────────────

  let whoDrawn = "";
  const who = popup<string>([], "", (id) => {
    editing = id;
    paint();
  }, { label: t("Character for") });

  // Classic first, then the six — each wearing whatever face is chosen now.
  // Its own row rather than more tiles in the grid: body and face are
  // independent, and folding them together would mean 7 x 18 tiles.
  const bodies: (MochiShape | null)[] = [null, ...SHAPES];
  const bodyTiles = bodies.map((shape) => tile(
    t(shape ? MOCHI_SHAPE_LABEL[shape] : "Classic"), BODY_SIZE, false, {
      shows: (c) => ({ accessory: c.accessory ?? null, eye: c.eye ?? null, shape }),
      chosen: (c) => (c.shape ?? null) === shape,
      picks: (c) => ({ ...c, shape }),
    }));

  // The face only: the body is the row above, so a Frog wearing Royal is
  // still Royal and the grid still says so.
  const faceTiles = CHARACTER_PRESETS.map((preset) => tile(t(preset.name), FACE_SIZE, false, {
    shows: (c) => ({
      accessory: preset.character.accessory ?? null,
      eye: preset.character.eye ?? null,
      shape: c.shape ?? null,
    }),
    chosen: (c) => sameFace(preset.character, c),
    picks: (c) => ({
      ...c,
      accessory: preset.character.accessory ?? null,
      eye: preset.character.eye ?? null,
    }),
  }));

  const accessories: PopupOption<MochiAccessory | "">[] = [
    { value: "", label: t("Nothing") },
    ...ACCESSORIES.map((a) => ({ value: a, label: t(ACCESSORY_LABEL[a]) })),
  ];
  const wearing = popup<MochiAccessory | "">(accessories, "", (v) => {
    write({ ...current(), accessory: v || null });
  }, { label: t("Wearing") });

  const eyeOptions: PopupOption<MochiEye | "">[] = [
    { value: "", label: t("As they come") },
    ...EYES.map((e) => ({ value: e, label: t(EYE_LABEL[e]) })),
  ];
  const eyes = popup<MochiEye | "">(eyeOptions, "", (v) => {
    write({ ...current(), eye: v || null });
  }, { label: t("Eyes") });

  const bodyHeading = heading(t("Body"));
  const faceHeading = heading(t("Face"));
  const wearHeading = heading(t("Wearing and eyes"));

  // An orb has no body to swap, no face to choose and nothing to wear but
  // Christmas.
  const mochiOnly: HTMLElement[] = [
    bodyHeading.el, grid(7, bodyTiles), divider(),
    faceHeading.el, grid(6, faceTiles), divider(),
    wearHeading.el, wearing, eyes,
  ];

  // ── Christmas ───────────────────────────────────────────────────────────────
  //
  // Everything a character can put on for Christmas, on top of whatever it
  // already is. Its own block rather than more entries in the two pickers: those
  // say who a pill is all year, and this comes off in January. Twelve outfits
  // ready to wear, then the four parts they are made of, each with a way back
  // to nothing.

  const { catalog } = festiveData();
  const festiveTiles: Tile[] = [];
  const festiveTile = (name: string, parts: Partial<Record<FestiveSlot, string | null>>,
    chosen: (c: MochiCharacter) => boolean): Tile => {
    const one = tile(name, FACE_SIZE, true, {
      shows: (c) => withFestive(c, parts),
      chosen,
      picks: (c) => withFestive(c, parts),
    });
    festiveTiles.push(one);
    return one;
  };
  const festiveRow = (title: string, tiles: Tile[]) =>
    stack(5, h("div", { class: "ch-row-title", text: title }), grid(6, tiles));

  // A preset sets all four parts at once, and is the chosen one only when all
  // four are exactly its own.
  const readyMade = festiveRow(t("Ready-made"), catalog.presets.map((preset) => {
    const parts = { head: preset.head, eyes: preset.eyes, texture: preset.texture, extra: preset.extra };
    return festiveTile(t(preset.name), parts,
      (c) => FESTIVE_SLOTS.every((slot) => (c.festive?.[slot] ?? null) === (parts[slot] ?? null)));
  }));

  // Nothing, then what the catalogue offers in its own order. Each tile
  // changes its one part and leaves the other three as they are.
  const partRow = (title: string, slot: FestiveSlot, options: [string, string][]) =>
    festiveRow(title, [
      festiveTile(t("None"), { [slot]: null }, (c) => !c.festive?.[slot]),
      ...options.map(([id, name]) =>
        festiveTile(t(name), { [slot]: id }, (c) => c.festive?.[slot] === id)),
    ]);

  const christmasHeading = heading(t("Christmas"));
  const badge = h("span", { class: "ch-badge", text: t("Until January 6") });
  const christmasDivider = divider();
  const christmas = stack(10,
    inlineRow(christmasHeading.el, badge),
    readyMade,
    partRow(t("Head"), "head", catalog.heads),
    partRow(t("Eyes"), "eyes", catalog.eyes),
    partRow(t("Texture"), "texture", catalog.textures),
    partRow(t("Extra"), "extra", catalog.extras),
  );

  // ── Back to the default ─────────────────────────────────────────────────────
  //
  // The Mac gives both buttons an 11pt font, which a bordered button on macOS
  // does not take: they draw at the regular size, and so do these.

  const useDefault = pushButton(t("Use the default for this one"), () => forget([editing]));

  // The default is not the last word, and nothing else here says so: a pill
  // with a face of its own keeps it, so changing the default above leaves that
  // pill exactly as it was. That is the whole "I changed it and nothing
  // happened".
  const overridingDivider = divider();
  const overridingText = hint("");
  const overriding = (): AgentTask[] =>
    INTEGRATION_AGENTS.filter((a) => settings.pillCharacters[a.id] != null);
  const overridingBlock = stack(4,
    overridingText,
    pushButton(t("Give them the default too"), () => forget(overriding().map((a) => a.id))),
  );

  const picker = groupBox({ title: null, gap: 12 },
    hint(t("Give each pill its own face. The colour still comes from the pill, so you always "
      + "know who is talking.")),
    who,
    ...mochiOnly,
    christmasDivider,
    christmas,
    useDefault,
    overridingDivider,
    overridingBlock,
  );
  picker.classList.add("ch-picker");

  // The grids stay on screen while the characters are hidden, dimmed and
  // inert: what has been put away can still be seen. `.disabled()` and, on
  // top of it, the Mac's own `.opacity(0.4)`.
  function dim() {
    disable(picker, settings.hideCharacters);
    picker.classList.toggle("mc-disabled", settings.hideCharacters);
  }

  function paint() {
    const c = current();
    const ato = editing === ATO_PILL;
    const open = christmasOpen();
    const color = pill(editing)?.color ?? DEFAULT_COLOR;
    const name = editing ? t(pill(editing)?.name ?? editing) : t("everyone else");

    // Ato is listed only while there is something for it here: in season, or
    // while it still wears something, or while it is the one being edited.
    const atoDressed = hasFestive(characterFromStorage(
      settings.pillCharacters[ATO_PILL] ?? settings.defaultCharacter));
    const pickable = INTEGRATION_AGENTS.filter((a) =>
      a.id !== ATO_PILL || ato || open || atoDressed);
    const list = pickable.map((a) => a.id).join(" ");
    if (list !== whoDrawn) {
      whoDrawn = list;
      who.setOptions([
        { value: "", label: t("Everyone else (default)") },
        ...pickable.map((a) => ({ value: a.id, label: t(a.name) })),
      ]);
    }
    who.set(editing);

    show(mochiOnly, !ato);
    if (!ato) {
      bodyHeading.set(name);
      faceHeading.set(name);
      wearHeading.set(name);
      paintTiles(bodyTiles, c, color, ato);
      paintTiles(faceTiles, c, color, ato);
      wearing.set(c.accessory ?? "");
      eyes.set(c.eye ?? "");
    }

    // There in season — and, out of it, for anyone still wearing something,
    // because a hat nobody can take off until next December is a trap.
    const showsChristmas = open || hasFestive(c);
    show([christmasDivider], showsChristmas && !ato);
    show([christmas], showsChristmas);
    if (showsChristmas) {
      christmasHeading.set(name);
      show([badge], open);
      paintTiles(festiveTiles, c, color, ato);
    }

    show([useDefault], editing !== "" && settings.pillCharacters[editing] != null);

    // Only while editing the default, which is what they are not getting. The
    // names go in as the Mac writes them, untranslated.
    const keeping = editing ? [] : overriding();
    show([overridingDivider, overridingBlock], keeping.length > 0);
    if (keeping.length) {
      overridingText.textContent = t(
        "Keeping a face of their own, so the default above does not reach them: %@.",
        keeping.map((a) => a.name).join(", "));
    }

    dim();
    // Once the shell has put the pane on screen — straight after this render,
    // or now, for a repaint.
    queueMicrotask(() => {
      if (picker.isConnected) fitNames(picker.box);
    });
  }

  paint();

  // Another window, the tray or the welcome changed something: the pane
  // follows, whoever it is editing.
  subscribe("settings", () => {
    hide.set(settings.hideCharacters);
    paint();
  });

  // Its first report is the pane landing on screen; its last, the pane taken
  // off it, when it lets go so the old canvases are not kept alive.
  const watch = new ResizeObserver(() => {
    if (picker.isConnected) {
      fitNames(picker.box);
      return;
    }
    watch.disconnect();
    if (resizeWatch === watch) resizeWatch = null;
  });
  resizeWatch = watch;
  watch.observe(picker.box);

  // The off switch holds a checkbox and a note, so its GroupBox is as wide as
  // the note's widest line, as the Mac's is; the picker's rows take the width.
  const body = stack(12, offSwitch, picker);
  hugBoxes(body, [offSwitch]);
  return [body];
}
