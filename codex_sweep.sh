#!/bin/bash
# codex_sweep.sh [timeout_s] "prompt…"  — run ONE codex web-search sweep with a HARD wall-clock cap.
#
# Kills the WHOLE process tree by PID on timeout (recursive, depth-first), NOT via a process-group
# signal. The old version used `set -m` + `kill -TERM -$pid` (negative pid = process group), but
# job control does NOT engage when this runs non-interactively (no controlling terminal) — e.g.
# under the scheduled `claude -p` compose agent. There the group kill silently failed and sweeps
# ran ~55 min against a 240s cap (observed 2026-10-29: 5 of 6 Garodia sweeps hung, brief went thin
# + 63-min compose). It "worked" only when tested by hand because an interactive shell has job
# control. pgrep/kill walk the real tree (codex node wrapper -> native codex binary) reliably.
T="${1:-240}"; shift
cd /tmp || exit 1

_killtree() {           # kill $1 and all descendants, leaves first (so children can't reparent)
  local p
  for p in $(pgrep -P "$1" 2>/dev/null); do _killtree "$p"; done
  kill -KILL "$1" 2>/dev/null
}

TO=$(mktemp 2>/dev/null || echo "/tmp/codexto.$$")
codex exec --skip-git-repo-check "$@" &
pid=$!
( sleep "$T"; _killtree "$pid"; echo 1 > "$TO" ) &
watch=$!
wait "$pid" 2>/dev/null
kill "$watch" 2>/dev/null; wait "$watch" 2>/dev/null

if [ -s "$TO" ]; then
  echo "[codex_sweep] TIMED_OUT after ${T}s — sweep killed, continue with other legs." >&2
fi
rm -f "$TO"
exit 0
