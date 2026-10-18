"""Flags closures that a @MainActor type hands to a queue that is not main.

See scripts/test-mainactor-dispatch.sh for why this exists. Two shapes cover
every way the app has actually got this wrong:

  1. DispatchSource.make*Source(..., queue: <not .main>)
  2. DispatchQueue.global(...) followed by .async / .asyncAfter / .sync

Only files that declare @MainActor somewhere are considered. A file with no
main-actor type in it can dispatch wherever it likes; there is no isolation to
violate. That keeps the rule narrow enough to carry no false positives today,
which matters more than catching every theoretical case: a check that cries
wolf is a check someone deletes.

A line genuinely needing a background queue says so:

    // swift-concurrency-ok: parses a 40 MB transcript, nothing captured
    DispatchQueue.global().async { heavyPureFunction() }
"""

from __future__ import annotations   # macOS ships python 3.9; `str | None` is 3.10

import re
import sys
from pathlib import Path

ALLOW = "swift-concurrency-ok:"

DISPATCH_SOURCE = re.compile(r"DispatchSource\.make\w*Source\s*\(")
QUEUE_LABEL = re.compile(r"\bqueue:\s*")
GLOBAL_QUEUE = re.compile(r"DispatchQueue\.global\s*\([^)]*\)\s*\.\s*(async|asyncAfter|sync)\b")


def queue_argument(text: str) -> str | None:
    """The `queue:` argument, whole. Counts parens rather than stopping at the
    first comma, or `.global(qos: .utility)` comes back cut at its own comma."""
    m = QUEUE_LABEL.search(text)
    if not m:
        return None
    depth = 0
    out = []
    for ch in text[m.end():]:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                break
            depth -= 1
        elif ch == "," and depth == 0:
            break
        out.append(ch)
    return "".join(out).strip()


def queue_is_main(arg: str) -> bool:
    return arg.strip() in (".main", "DispatchQueue.main")


def scan(path: Path) -> list[tuple[int, str, str]]:
    """Returns (line number, offending source, why) for one file."""
    text = path.read_text(encoding="utf-8")
    if "@MainActor" not in text:
        return []

    lines = text.splitlines()
    found = []
    for i, line in enumerate(lines):
        # The waiver sits on the line above, where it can explain itself.
        if i > 0 and ALLOW in lines[i - 1]:
            continue
        if ALLOW in line:
            continue

        if DISPATCH_SOURCE.search(line):
            # The queue: label may be on this line or a continuation of it.
            arg = queue_argument(" ".join(lines[i:i + 3]))
            if arg and not queue_is_main(arg):
                found.append((i + 1, line.strip(),
                              f"dispatch source on {arg}, not .main"))

        if GLOBAL_QUEUE.search(line):
            found.append((i + 1, line.strip(),
                          "work scheduled on DispatchQueue.global()"))
    return found


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "NotchBuddy/Sources/App")
    swift_files = sorted(root.rglob("*.swift"))
    if not swift_files:
        print(f"  ✗ no Swift sources under {root}")
        return 1

    failures = 0
    for path in swift_files:
        for lineno, source, why in scan(path):
            print(f"  ✗ {path}:{lineno}")
            print(f"      {source}")
            print(f"      {why}")
            failures += 1

    print("")
    if failures == 0:
        print(f"No @MainActor closure goes to a background queue "
              f"({len(swift_files)} files checked).")
        return 0
    print(f"{failures} closure(s) a @MainActor type hands to a background queue.")
    print("Swift 6 traps on these at runtime, not at build time — the app just "
          "disappears.")
    print("Move the work to DispatchQueue.main, or waive the line with "
          f"// {ALLOW} <reason>.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
