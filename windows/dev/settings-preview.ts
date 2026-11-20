// Dev harness: every visible Settings section, light and dark side by side, at
// the Mac window's 720x560. Each frame is the real settings.html in a plain
// browser — Bridge calls are no-ops outside Tauri and the store fills in
// stand-in boot data — with `?section=` and `?scheme=` choosing what it shows.
// Not part of the app bundle.
//
//   cd windows && ./node_modules/.bin/vite   →   /dev/settings-preview.html
//
// The "Mac" links open the reference captures (scripts/capture-mac-reference.sh)
// when this Mac has taken them; /dev/compare.html overlays one on the other.

import { visibleSections } from "../src/settings/sections";

const SCHEMES = ["light", "dark"] as const;

/** The capture to compare a section with: the Dynamic Island pane has one per tab. */
function macCapture(id: string, scheme: string): string {
  const name = id === "island" ? "island-layout" : id;
  return `/mac-captures/settings/${name}-${scheme}.png`;
}

const grid = document.getElementById("grid")!;
const zoom = document.getElementById("zoom") as HTMLSelectElement;
const only = document.getElementById("only") as HTMLSelectElement;

for (const s of visibleSections()) {
  const o = document.createElement("option");
  o.value = s.id;
  o.textContent = s.title;
  only.append(o);
}

function render() {
  const scale = Number(zoom.value) || 1;
  grid.replaceChildren();
  for (const section of visibleSections()) {
    if (only.value && only.value !== section.id) continue;
    const pair = document.createElement("div");
    pair.className = "pair";
    for (const scheme of SCHEMES) {
      const cell = document.createElement("div");
      cell.className = "cell";
      const label = document.createElement("div");
      label.className = "label";
      label.innerHTML = `<span>${section.title} · ${scheme}</span>`;
      const mac = document.createElement("a");
      mac.href = macCapture(section.id, scheme);
      mac.target = "_blank";
      mac.textContent = "Mac";
      label.append(mac);
      const holder = document.createElement("div");
      holder.className = "holder";
      holder.style.width = `${720 * scale}px`;
      holder.style.height = `${560 * scale}px`;
      const frame = document.createElement("iframe");
      frame.className = "frame";
      frame.src = `../settings.html?section=${section.id}&scheme=${scheme}`;
      frame.style.transform = `scale(${scale})`;
      holder.append(frame);
      cell.append(label, holder);
      pair.append(cell);
    }
    grid.append(pair);
  }
}

zoom.addEventListener("change", render);
only.addEventListener("change", render);
render();
