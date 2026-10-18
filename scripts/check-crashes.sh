#!/usr/bin/env bash
# Did the app fall over? Reads the crash reports macOS already wrote.
#
# An island that vanishes looks exactly like an island that auto-closed, and a
# Swift 6 isolation trap leaves nothing in the app's own log — so "it crashed
# out of nowhere" is a thing you can only answer from .ips files. Thirty-five
# of them, all one bug, sat unread between 2026-10-12 and 2026-10-18.
#
# Fails only on crashes newer than the installed build: older ones came out of
# code that is gone, and a check that keeps shouting about history is one
# nobody reads. That also means it goes green on its own once a fix is
# installed, with no baseline file to keep up to date.
#
# Local tool. It reads ~/Library/Logs, never leaves the machine, and ships in
# nothing — the app still has no crash reporting, as docs/privacy.html says.
# Not in CI either: a GitHub runner has no crash reports to read.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I scripts/crash_report_reader.py
