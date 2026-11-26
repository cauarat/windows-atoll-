// Active pills — the Mac's activePillsSection and pillRow (SettingsView.swift):
// one untitled GroupBox saying which pills are switched on, how many of the
// four slots that spends, and what Home shows. Every pill switch lives here,
// as it does on the Mac — the message services' sign-in blocks under
// Integrations no longer carry one.

import "./activePills.css";
import { t } from "../../core/i18n";
import {
  HOME_CONTENTS, HOME_HINT, HOME_LABEL, INTEGRATION_AGENTS, type AgentTask, type HomeContent,
} from "../../core/state";
import { h } from "../../views/dom";
import {
  caption, checkbox, colorDot, divider, groupBox, hint, inlineRow, popup, spacer,
  type Checkbox, type Child, type PopupOption,
} from "../controls";
import { MAX_ACTIVE, boot, emit, save, settings, subscribe } from "../store";

/**
 * PillCategory's one case, and the caption the list is drawn under. English:
 * it is the catalogue key, translated where it is drawn. "Where you code" held
 * Claude Code alone, and went with it; every pill left is a service.
 */
const SERVICES_TITLE = "Services";

/**
 * `PillCatalog.available`: every declared pill, in the catalogue's order,
 * except Now Playing where this build cannot read what is playing (Linux). The
 * Mac leaves pills out of its App Store build the same way.
 */
function availablePills(): AgentTask[] {
  return INTEGRATION_AGENTS.filter((p) => p.id !== "integration_music" || boot.media);
}

/**
 * `AppState.toggleIntegration`: a pill only goes on while one of the four
 * slots is free.
 */
function togglePill(id: string): void {
  const active = settings.activeIntegrations;
  if (active.includes(id)) {
    settings.activeIntegrations = active.filter((x) => x !== id);
  } else if (active.length < MAX_ACTIVE) {
    settings.activeIntegrations = [...active, id];
  } else {
    // Unreachable through the disabled checkbox; repaint so it unticks.
    emit("active");
    return;
  }
  emit("active");
  void save();
}

/** One row of the list, and what has to be repainted in it. */
interface PillRow {
  id: string;
  row: HTMLElement;
  name: HTMLElement;
  box: Checkbox;
}

/**
 * `pillRow`: a 10px dot, the name at 12px, and a checkbox on the far end. With
 * all four slots taken, a pill that is off greys its name and its checkbox
 * stops answering.
 */
function pillRow(def: AgentTask): PillRow {
  const name = h("span", { class: "ap-name", text: t(def.name) });
  const box = checkbox("", settings.activeIntegrations.includes(def.id), () => togglePill(def.id),
    { ariaLabel: t(def.name) });
  const row = inlineRow(colorDot(def.color, 10), name, spacer(), box);
  row.classList.add("ap-row");
  return { id: def.id, row, name, box };
}

/** What the "Home shows" popup offers, in HomeContent's order. */
function homeOptions(): PopupOption<HomeContent>[] {
  return HOME_CONTENTS.map((value) => ({ value, label: t(HOME_LABEL[value]) }));
}

/** The hint under the popup, so the choice explains itself. */
function homeHintText(): string {
  // A stored value this build does not list yet has no hint rather than a crash.
  const key = HOME_HINT[settings.homeContent as HomeContent] as string | undefined;
  return key ? t(key) : "";
}

/** The Active pills pane. */
export function render(): Node[] {
  const slots = hint("");
  slots.classList.add("ap-slots");

  const homeHint = hint(homeHintText());
  const home = popup<HomeContent>(homeOptions(), settings.homeContent, (value) => {
    settings.homeContent = value;
    homeHint.textContent = homeHintText();
    void save();
  }, { label: t("Home shows") });

  const rows = availablePills().map(pillRow);
  const list: Child[] = rows.length > 0
    ? [divider(), caption(t(SERVICES_TITLE)), ...rows.map((row) => row.row)]
    : [];

  /** Everything that follows the pill set and the Home choice, in place. */
  function paint(): void {
    const active = settings.activeIntegrations;
    const count = active.length;
    slots.textContent = t("%lld/4 slots used", count);
    slots.classList.toggle("full", count >= MAX_ACTIVE);
    for (const { id, name, box } of rows) {
      const on = active.includes(id);
      const atMax = count >= MAX_ACTIVE && !on;
      box.set(on);
      box.setDisabled(atMax);
      name.classList.toggle("at-max", atMax);
    }
    // Another window, or the island, may have changed it.
    if (home.value() !== settings.homeContent) home.set(settings.homeContent);
    homeHint.textContent = homeHintText();
  }

  subscribe("active", paint);
  subscribe("settings", paint);
  paint();

  return [
    groupBox({ title: null, gap: 10 },
      hint(t("Choose the tools you use. Notchy only shows what you declare here.")),
      slots,
      home,
      homeHint,
      ...list,
    ),
  ];
}
