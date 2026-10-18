"""Reads the Mac's own crash reports for Notchy and says what fell over, where.

See scripts/check-crashes.sh for the why. This is a development tool: it runs
on the machine of whoever is working on the app, reads files macOS has already
written locally, and sends nothing anywhere. The app itself still has no crash
reporting of any kind, which is what docs/privacy.html promises.

An .ips file is one line of JSON header followed by a JSON body. The crash site
is the first frame of the faulting thread whose image is the app's own — in a
Debug build that is Notchy.debug.dylib, because the Notchy executable beside it
is a 40 KB stub with none of the code in it.
"""

from __future__ import annotations   # macOS ships python 3.9

import json
import os
import sys
from collections import OrderedDict
from datetime import datetime
from pathlib import Path

APP_IMAGES = ("Notchy", "NotchBuddy")
DEFAULT_APP = Path("/Applications/Notchy.app/Contents/MacOS")


def report_dirs() -> list[Path]:
    """Where macOS keeps them. COUCOU_CRASH_DIR overrides, so the failure path
    can be exercised without having to crash the real app."""
    override = os.environ.get("COUCOU_CRASH_DIR")
    if override:
        return [Path(override)]
    base = Path.home() / "Library/Logs/DiagnosticReports"
    # Reports age out of the top level into Retired/ but are the same crashes.
    return [base, base / "Retired"]


def build_time() -> datetime | None:
    """When the installed app was built. Crashes older than this came out of
    code that no longer exists, so they are history, not a live problem."""
    app = Path(os.environ.get("COUCOU_APP_DIR", DEFAULT_APP))
    if not app.is_dir():
        return None
    stamps = [p.stat().st_mtime for p in app.iterdir() if p.is_file()]
    if not stamps:
        return None
    return datetime.fromtimestamp(max(stamps)).astimezone()


def parse(path: Path) -> tuple[datetime, str, str] | None:
    """(when, exception type, crash site) for one report."""
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
        header, body = raw.split("\n", 1)
        head = json.loads(header)
        data = json.loads(body)
    except (ValueError, OSError):
        return None   # a half-written report is not worth a stack trace

    try:
        when = datetime.strptime(head["timestamp"], "%Y-%m-%d %H:%M:%S.%f %z")
    except (KeyError, ValueError):
        when = datetime.fromtimestamp(path.stat().st_mtime).astimezone()

    kind = (data.get("exception") or {}).get("type", "?")

    images = data.get("usedImages", [])
    site = "no frame in the app's own code"
    for frame in data.get("threads", [])[data.get("faultingThread", 0)].get("frames", []):
        name = images[frame.get("imageIndex", 0)].get("name", "") if images else ""
        if any(name.startswith(a) for a in APP_IMAGES):
            site = frame.get("symbol") or f"{name}+{frame.get('imageOffset')}"
            break
    return when, kind, site


def main() -> int:
    reports = []
    for d in report_dirs():
        if d.is_dir():
            reports.extend(d.glob("Notchy-*.ips"))
            reports.extend(d.glob("NotchBuddy-*.ips"))

    parsed = sorted(filter(None, (parse(p) for p in reports)))
    built = build_time()

    if not parsed:
        print("  ✓ no crash reports for Notchy on this Mac.")
        return 0

    # Group by where it crashed: thirty-five reports of one bug is one bug.
    groups: OrderedDict[tuple[str, str], list[datetime]] = OrderedDict()
    for when, kind, site in parsed:
        groups.setdefault((kind, site), []).append(when)

    since_build = 0
    for (kind, site), times in sorted(groups.items(), key=lambda kv: max(kv[1]), reverse=True):
        fresh = [t for t in times if built and t > built] if built else []
        since_build += len(fresh)
        mark = "✗" if fresh else "·"
        print(f"  {mark} {len(times):>3} ×  {kind}  {site}")
        span = times[0].strftime("%Y-%m-%d %H:%M")
        if len(times) > 1:
            span += "  →  " + times[-1].strftime("%Y-%m-%d %H:%M")
        tail = f"   ({len(fresh)} since the installed build)" if fresh else ""
        print(f"        {span}{tail}")

    print("")
    if built is None:
        print("Notchy is not installed in /Applications, so none of these can be "
              "tied to a build. Reporting only.")
        return 0
    if since_build == 0:
        print(f"{len(parsed)} crash(es) on record, none since the installed build "
              f"of {built.strftime('%Y-%m-%d %H:%M')}.")
        return 0
    print(f"{since_build} crash(es) since the installed build of "
          f"{built.strftime('%Y-%m-%d %H:%M')} — the running app still has this.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
