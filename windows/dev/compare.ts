// Mac reference beside the Windows page it should match. Dev only: nothing here
// ships. See docs/parity/README.md.

type Mode = "side" | "diff" | "onion";

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const mac = $<HTMLSelectElement>("mac");
const win = $<HTMLInputElement>("win");
const w = $<HTMLInputElement>("w");
const h = $<HTMLInputElement>("h");
const bar = $<HTMLInputElement>("bar");
const opacity = $<HTMLInputElement>("opacity");
const stage = $<HTMLElement>("stage");
const params = new URLSearchParams(location.search);
let mode: Mode = (params.get("mode") as Mode) ?? "side";

function frame(): HTMLIFrameElement {
  const f = document.createElement("iframe");
  f.src = win.value;
  f.width = w.value;
  f.height = h.value;
  return f;
}

function image(): HTMLImageElement {
  const img = document.createElement("img");
  if (mac.value) img.src = `/mac-captures/${mac.value}`;
  // Drawn at the page's width whatever the capture's scale: a 2x capture of a
  // 720 pt window is 1440 px wide, a 1x one 720.
  img.style.width = `${w.value}px`;
  return img;
}

function render() {
  stage.replaceChildren();
  $("opacity-row").style.display = mode === "onion" ? "" : "none";
  for (const b of document.querySelectorAll<HTMLButtonElement>(".modes button")) {
    b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
  }
  if (mode === "side") {
    const pane = (title: string, el: HTMLElement) => {
      const p = document.createElement("div");
      p.className = "pane";
      const t = document.createElement("h1");
      t.textContent = title;
      p.append(t, el);
      return p;
    };
    const row = document.createElement("div");
    row.className = "side";
    row.append(pane(`Mac — ${mac.value || "no capture"}`, image()), pane(`Windows — ${win.value}`, frame()));
    stage.append(row);
  } else {
    const stack = document.createElement("div");
    stack.className = "stack";
    const f = frame();
    f.classList.add("over");
    f.style.top = `${bar.value}px`;
    if (mode === "diff") f.classList.add("diff");
    else f.style.opacity = String(Number(opacity.value) / 100);
    stack.append(image(), f);
    stage.append(stack);
  }
  const q = new URLSearchParams({ mac: mac.value, win: win.value, w: w.value, h: h.value, bar: bar.value, mode });
  history.replaceState(null, "", `?${q}`);
}

async function boot() {
  const files: string[] = await fetch("/mac-captures/index.json").then((r) => r.json()).catch(() => []);
  mac.replaceChildren(...files.map((f) => new Option(f, f)));
  if (files.length === 0) mac.append(new Option("— run scripts/capture-mac-reference.sh —", ""));
  for (const [key, el] of [["mac", mac], ["win", win], ["w", w], ["h", h], ["bar", bar]] as const) {
    const v = params.get(key);
    if (v !== null) el.value = v;
  }
  for (const el of [mac, win, w, h, bar]) el.addEventListener("change", render);
  opacity.addEventListener("input", () => {
    const f = stage.querySelector<HTMLIFrameElement>("iframe.over");
    if (f) f.style.opacity = String(Number(opacity.value) / 100);
  });
  for (const b of document.querySelectorAll<HTMLButtonElement>(".modes button")) {
    b.addEventListener("click", () => { mode = b.dataset.mode as Mode; render(); });
  }
  render();
}

void boot();
