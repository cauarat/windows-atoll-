// Dev harness: the welcome's seven screens side by side, each one the real
// page (onboarding.html, standalone — no Rust behind it, so it makes its own
// settings up) in a 520×660 frame, the Mac's window size, so the lot can be
// screenshotted next to the Mac's own screens at 1x. Not in the bundle.
//
// `npx vite`, then /dev/onboarding-preview.html. Everything in the query is
// handed to each frame — `lang=pt-BR`, `name=Ana`, `character=<stored
// character>`, `pills=<id,id>`, `account=<full name>`, `media=0` — and
// `step=look` keeps one screen. The look screen also takes `tab=face`, `body`
// or `christmas` and `editing=<pill id>` (`integration_ato` for Ato), so each
// tab and each pill's Mochi can be put up. Inside a frame,
// `welcome.show("tools")` moves it and `welcome.step(0.016)` draws Mochi a
// frame on.

import { ONBOARDING_STEPS } from "../src/core/onboarding";

const query = new URLSearchParams(location.search);
const only = query.get("step");
const frames = document.getElementById("frames")!;
// Said under the look screen, which is the one they change.
const look = [query.get("tab"), query.get("editing")].filter(Boolean).join(" · ");

for (const step of ONBOARDING_STEPS) {
  if (only && only !== step) continue;
  const params = new URLSearchParams(query);
  params.set("step", step);
  const frame = document.createElement("iframe");
  frame.src = `../onboarding.html?${params.toString()}`;
  frame.title = step;
  const caption = document.createElement("figcaption");
  caption.textContent = step === "look" && look ? `${step} · ${look}` : step;
  const figure = document.createElement("figure");
  figure.append(frame, caption);
  frames.append(figure);
}
