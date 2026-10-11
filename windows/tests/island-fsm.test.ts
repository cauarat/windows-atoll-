export {}; // top-level await needs this file to be a module

// Mirror of tests/IslandStateMachineTests.swift: the two FSMs are ports of one
// another, so they are held to the same checks.
function equal(actual: unknown, expected: unknown, message: string) {
  if (actual !== expected) {
    throw new Error(`${message} — expected ${String(expected)}, got ${String(actual)}`);
  }
}

function notEqual(actual: unknown, expected: unknown, message: string) {
  if (actual === expected) {
    throw new Error(`${message} — got ${String(actual)}`);
  }
}

// The FSM schedules on `window`, which node has no notion of. Hand it real
// timers behind numeric ids, the way a browser does.
const timers = new Map<number, ReturnType<typeof setTimeout>>();
let nextId = 1;
(globalThis as any).window = {
  setTimeout(fn: () => void, ms: number): number {
    const id = nextId++;
    timers.set(id, setTimeout(() => { timers.delete(id); fn(); }, ms));
    return id;
  },
  clearTimeout(id: number) {
    const t = timers.get(id);
    if (t !== undefined) { clearTimeout(t); timers.delete(id); }
  },
};

const { IslandStateMachine } = await import("../src/island/fsm.js");

const pump = (seconds: number) => new Promise((r) => setTimeout(r, seconds * 1000));

function fresh() {
  const fsm = new IslandStateMachine();
  // Short enough to keep the suite quick, far enough apart to tell the hover
  // grace and the deliberate-open interval from one another.
  fsm.hoverOpenDelayFromHidden = 0.05;
  fsm.hoverOpenDelayFromPetit = 0.05;
  fsm.hoverCloseDelay = 0.05;
  fsm.homeToPetitDelay = 10;
  fsm.petitToHiddenDelay = 10;
  return fsm;
}

// Hover peeks at once, then opens on its own once the cursor has dwelt.
{
  const fsm = fresh();
  fsm.mouseEntered();
  equal(fsm.state, "petit", "hover should peek before it opens");
  await pump(0.15);
  equal(fsm.state, "home", "dwelling on the island should open it");
}

// A cursor crossing the top of the screen must not drag the panel open behind it.
{
  const fsm = fresh();
  fsm.mouseEntered();
  fsm.mouseLeft();
  await pump(0.15);
  notEqual(fsm.state, "home", "a sweep past the island must never open it");
}

// Leaving closes it again — all the way back to hidden, since that is where the
// hover started. Anything less parks a bar on screen.
{
  const fsm = fresh();
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "home", "should be open by now");
  fsm.mouseLeft();
  await pump(0.15);
  equal(fsm.state, "hidden", "a hover that started from hidden should close to hidden");
}

// Hovering a compact island opens it, and leaving returns it to compact: there
// is live work behind it, so it must not vanish.
{
  const fsm = fresh();
  fsm.reveal();
  equal(fsm.state, "petit", "should be compact by now");
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "home", "hovering the compact island should open it");
  fsm.mouseLeft();
  await pump(0.15);
  equal(fsm.state, "petit", "a hover that started from compact should close to compact");
}

// Coming back during the grace cancels the close, so brushing an edge does not
// flicker the island shut.
{
  const fsm = fresh();
  fsm.mouseEntered();
  await pump(0.15);
  fsm.mouseLeft();
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "home", "returning during the grace should keep it open");
}

// A pending approval outranks the cursor: answering it must not be snatched away
// by walking the mouse off the island.
{
  const fsm = fresh();
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "home", "should be open by now");
  fsm.pinned = true;
  fsm.mouseLeft();
  await pump(0.15);
  equal(fsm.state, "home", "a pinned island must survive the cursor leaving");
}

// Clicking inside promotes it: from then on it follows Auto-close, not the hover
// grace, so reading something you clicked into is not a race.
{
  const fsm = fresh();
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "home", "should be open by now");
  fsm.engaged();
  fsm.mouseLeft();
  await pump(0.15);
  equal(fsm.state, "home", "a clicked-into island should keep the Auto-close interval");
}

// Clicking the compact island opens it deliberately, and that open also outlives
// the cursor leaving.
{
  const fsm = fresh();
  fsm.reveal();
  fsm.click();
  equal(fsm.state, "home", "should be open by now");
  fsm.mouseLeft();
  await pump(0.15);
  equal(fsm.state, "home", "a click-opened island should not close on the hover grace");
}

// The greeting still wins over hover: it opens on launch and the cursor leaving
// interrupts it to compact, exactly as before.
{
  const fsm = fresh();
  fsm.launch();
  equal(fsm.state, "coucou", "launch should play the greeting");
  fsm.mouseEntered();
  equal(fsm.state, "coucou", "hover must not reopen the greeting as home");
  fsm.mouseLeft();
  equal(fsm.state, "petit", "leaving the greeting should interrupt it to compact");
}

// The two dwells are independent, and the one for an idle island is the slower:
// crossing the top of the screen should cost more patience than brushing a
// compact island that is already on screen.
{
  const fsm = fresh();
  fsm.hoverOpenDelayFromHidden = 0.3;
  fsm.hoverOpenDelayFromPetit = 0.05;
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "petit", "the hidden dwell should still be running");
  await pump(0.3);
  equal(fsm.state, "home", "the hidden dwell should have opened it by now");
}
{
  const fsm = fresh();
  fsm.hoverOpenDelayFromHidden = 0.3;
  fsm.hoverOpenDelayFromPetit = 0.05;
  fsm.reveal();
  fsm.mouseEntered();
  await pump(0.15);
  equal(fsm.state, "home", "the compact dwell is the short one");
}

console.log("IslandStateMachine (Windows): all checks passed");
