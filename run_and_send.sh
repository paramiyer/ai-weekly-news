#!/bin/bash
# Weekly AI brief: compose fresh, hold to the configured send time, send, record.
# Fires Monday (launchd); if woken early it composes then HOLDS (machine kept awake) to the
# send time, so content is fresh and the send lands on time. Mirrors the Garodia single-job design.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.env"
SKILL="$HERE/SKILL.md" ; MSG=/tmp/ai-message.txt ; SEL=/tmp/ai-selected.json
LOG=/tmp/ai-news.log ; BRIDGE_DIR="$HOME/mcp-servers/whatsapp-mcp/whatsapp-bridge"
WE=$(date +%Y-%m-%d)                                   # this Monday = window end
WS=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
DEST="${GROUP_JID:-$SEND_JID}" ; [ -n "$SEND_JID" ] && [ -z "$GROUP_JID" ] && DEST="$SEND_JID"
log(){ echo "[$(TZ=$TZ_SEND date '+%F %H:%M:%S') $TZ_SEND] $*" >>"$LOG"; }

caffeinate -i -s -w $$ & disown                        # strong assertion: survive a closed lid

# idempotency: already sent this week?
if sqlite3 "$HERE/state.db" "select 1 from executions where execution_id='ai-news-$WE' and send_result like 'SUCCESS%';" 2>/dev/null | grep -q 1; then
  log "already sent this week ($WE) — exit."; exit 0; fi

# bridge preflight: start the Go bridge if :8080 is down
if [ "$(curl -s -m3 -o /dev/null -w '%{http_code}' "$BRIDGE_URL" -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null)" = "000" ]; then
  log "bridge down — starting it."; ( cd "$BRIDGE_DIR" && nohup ./main >/tmp/wa-bridge.log 2>&1 & )
  for i in $(seq 1 20); do sleep 1; [ "$(curl -s -m3 -o /dev/null -w '%{http_code}' "$BRIDGE_URL" -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null)" != "000" ] && break; done
fi

# 1) FRESH compose (writes MSG + SEL). Retry once after the usage-limit reset if we hit it.
_compose(){
  STAMP=$(date +%s); rm -f "$MSG"
  _pre=$(wc -l <"$LOG" 2>/dev/null | tr -d ' ')
  /opt/homebrew/bin/claude -p \
    "COMPOSE ONLY. Read and follow $SKILL for the window $WS to $WE. render_brief.py writes $MSG and $SEL. Do NOT send. Print the message and end with BOT_RESULT: COMPOSED." \
    --allowedTools "Bash Read WebSearch WebFetch" --permission-mode dontAsk >>"$LOG" 2>&1
}
_is_fresh(){ [ -s "$MSG" ] && [ "$(stat -f %m "$MSG" 2>/dev/null || stat -c %Y "$MSG")" -ge "$STAMP" ]; }
_hit_limit(){ tail -n +"$((_pre+1))" "$LOG" 2>/dev/null | grep -qiE "hit your (usage|session|monthly) limit|spend limit|resets [0-9]"; }

log "=== compose start ($WS -> $WE) ==="
_compose
if ! _is_fresh && _hit_limit; then
  WAKE=$(python3 -c "
import re,datetime as dt
txt=open('$LOG').read()
m=re.findall(r'resets (\d{1,2}):(\d{2})\s*(am|pm)?', txt, re.I)
tz=dt.timezone(dt.timedelta(hours=4)); now=dt.datetime.now(tz)
if m:
    h,mn,ap=m[-1]; h=int(h)%12+(12 if (ap or '').lower()=='pm' else 0)
    t=now.replace(hour=h,minute=int(mn),second=0,microsecond=0)
    if t<=now: t+=dt.timedelta(days=1)
    wait=int((t-now).total_seconds())+300
else: wait=3600
print(max(60,min(wait,5400)))")
  log "compose hit the usage limit — waiting ${WAKE}s for reset, then ONE retry."
  sleep "$WAKE"; log "=== compose retry (post-reset) ==="; _compose
fi

# 2) freshness gate
if ! _is_fresh; then
  log "NO FRESH message (compose failed / still limited). Alerting, NOT sending."
  curl -s -m10 -X POST "$BRIDGE_URL" -H 'Content-Type: application/json' \
   -d "$(python3 -c "import json;print(json.dumps({'recipient':'$ALERT_JID','message':'⚠️ AI weekly: no fresh brief composed (compose failed or quota out). Check $LOG'}))")" >>"$LOG" 2>&1
  exit 1
fi
log "fresh compose OK ($(stat -f %Sm "$MSG" 2>/dev/null))."

# 3) HOLD until the configured send time (cap 240 min covers an early wake)
"$HERE/wait_until.sh" "$SEND_HOUR" "$SEND_MIN" 14400 >>"$LOG" 2>&1

# 4) SEND + record
BODY=$(python3 -c "import json;print(json.dumps({'recipient':'$DEST','message':open('$MSG').read()}))")
RESP=$(curl -s -m20 -X POST "$BRIDGE_URL" -H 'Content-Type: application/json' -d "$BODY")
log "bridge: $RESP"
if echo "$RESP" | grep -q '"success":true'; then
  log "SENT to $DEST at $(TZ=$TZ_SEND date '+%H:%M %Z')."
  [ -s "$SEL" ] && python3 "$HERE/record.py" --commit "$SEL" --week-end "$WE" --dest "$DEST" --counts "window_start=$WS" >>"$LOG" 2>&1
  echo "BOT_RESULT: SUCCESS" >>"$LOG"
else
  log "SEND FAILED. Alerting."
  curl -s -m10 -X POST "$BRIDGE_URL" -H 'Content-Type: application/json' \
   -d "$(python3 -c "import json;print(json.dumps({'recipient':'$ALERT_JID','message':'⚠️ AI weekly failed to send. Check $LOG'}))")" >>"$LOG" 2>&1
  exit 1
fi
