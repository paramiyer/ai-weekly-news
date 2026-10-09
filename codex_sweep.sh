#!/bin/bash
# codex_sweep.sh [timeout_s] "prompt…"  — run ONE codex web-search sweep with a HARD wall-clock
# cap, because codex sweeps have no native timeout and occasionally hang 20-60 min, which used to
# push the 7:00 IST send to 08:30-09:12 and gut blocked-outlet coverage (seen Sep-Oct 2026).
#
# NOTE: `perl -e 'alarm'` does NOT kill codex (Node resets SIGALRM) — verified it ran to 174s under
# a 150s alarm. So this uses a real watchdog: SIGTERM at the cap, SIGKILL 5s later, kill the whole
# process group so codex's children die too.
#
# Exit 0 on a clean finish OR a timeout (timeout = "no result this leg, move on"); the sweep's
# stdout (full or partial) is printed either way. A timed-out sweep prints a TIMED_OUT marker.
T="${1:-240}"; shift
cd /tmp || exit 1
set -m                                   # own process group for the child
codex exec --skip-git-repo-check "$@" &
pid=$!
( sleep "$T"; kill -TERM -"$pid" 2>/dev/null; sleep 5; kill -KILL -"$pid" 2>/dev/null ) &
watch=$!
wait "$pid" 2>/dev/null; rc=$?
kill "$watch" 2>/dev/null; wait "$watch" 2>/dev/null
# rc 143 = SIGTERM, 137 = SIGKILL -> we hit the cap
if [ "$rc" = 143 ] || [ "$rc" = 137 ]; then
  echo "[codex_sweep] TIMED_OUT after ${T}s — sweep skipped, continue with other legs." >&2
fi
exit 0
