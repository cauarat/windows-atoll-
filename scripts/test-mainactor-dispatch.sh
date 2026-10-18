#!/usr/bin/env bash
# A closure written inside a @MainActor type must not be handed to a queue that
# is not the main one.
#
# In Swift 6 language mode such a closure inherits @MainActor isolation, and the
# compiler plants a runtime isolation check at its entry. It cannot prove which
# queue Dispatch will call it on, so this is not a build error — it is a
# dispatch_assert_queue failure and a SIGTRAP, in front of the user, with the
# app simply vanishing. Thirty-five crash reports between 2026-10-12 and
# 2026-10-18 were one timer written this way.
#
# This reads the source rather than compiling it, which is why it lives next to
# the parity checks rather than among the swiftc suites.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I scripts/mainactor_dispatch_check.py NotchBuddy/Sources/App
