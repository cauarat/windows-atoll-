// Settings window — boot only: load the preferences into the store, build the
// shell (sidebar + detail pane, as the Mac's SettingsView), register a render
// function per pane. Each pane lives in ./panes/<pane>.ts.

import "./settings.css";
import { Hydration } from "../core/hydrationStore";
import { loadStore } from "./store";
import { listenForSections, mountShell, registerPane, selectSection } from "./shell";
import * as general from "./panes/general";
import * as activePills from "./panes/activePills";
import * as island from "./panes/island";
import * as chat from "./panes/chat";
import * as integrations from "./panes/integrations";
import * as characters from "./panes/characters";
import * as hydration from "./panes/hydration";
import * as dictation from "./panes/dictation";

async function main() {
  // First, so a deep link that arrives while the window boots is kept.
  listenForSections();
  await loadStore();

  // Hydration keeps its own state, in localStorage, which this window shares
  // with the island. "settings": it reads and writes, and arms no reminder.
  Hydration.load("settings");
  // "Answer the questions" on the island: the island asks through the store,
  // and Rust's "settings-section" brings this pane up as well. Either order
  // ends on the questions' first screen.
  Hydration.onSetupAsked = () => {
    hydration.askHydrationSetup();
    selectSection("hydration");
  };

  registerPane("general", general.render);
  registerPane("activepills", activePills.render);
  registerPane("island", island.render);
  registerPane("chat", chat.render);
  registerPane("dictation", dictation.render);
  registerPane("integrations", integrations.render);
  registerPane("characters", characters.render);
  registerPane("hydration", hydration.render);

  mountShell(document.getElementById("settings-root")!);
}

void main();
