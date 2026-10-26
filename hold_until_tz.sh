#!/bin/bash
# hold_until_tz.sh TZ HH MM [max_early_seconds]
# Sleep until today's HH:MM in the NAMED timezone TZ — computed as an absolute epoch, so it is
# correct no matter what timezone the machine's own clock is set to (travel-proof). If that moment
# has already passed, return immediately (prints how late). Caps the wait at max_early_seconds
# (default 10800) so a very early fire can't hang indefinitely.
#
# Replaces wait_until.sh (which held to a machine-LOCAL HH:MM and therefore drifted when the Mac's
# timezone changed, e.g. Dubai -> Mumbai in Oct 2026).
TZN="$1"; HH="$2"; MM="$3"; MAX="${4:-10800}"
day=$(TZ="$TZN" date +%Y-%m-%d)
target=$(TZ="$TZN" date -j -f "%Y-%m-%d %H:%M:%S" "$day $HH:$MM:00" +%s 2>/dev/null) || { echo "[hold] could not compute target"; exit 0; }
now=$(date +%s)
delta=$(( target - now ))
if [ "$delta" -gt 0 ]; then
  if [ "$delta" -gt "$MAX" ]; then
    echo "[hold] ${HH}:${MM} ${TZN} is $(( delta/60 ))m away (> cap $(( MAX/60 ))m) — not holding, proceeding now."
    exit 0
  fi
  echo "[hold] holding $(( delta/60 ))m until ${HH}:${MM} ${TZN} (machine tz: $(date '+%Z'))."
  sleep "$delta"
  echo "[hold] resumed at $(TZ="$TZN" date '+%H:%M %Z')."
else
  echo "[hold] ${HH}:${MM} ${TZN} already passed by $(( -delta/60 ))m — proceeding now."
fi
