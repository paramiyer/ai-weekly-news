# AI Weekly — a self-running weekly AI-news bot for WhatsApp

A small, config-driven agent that every **Monday** surfaces the week's most important AI news,
scores and filters it, summarises it, and sends a clean brief to a WhatsApp chat. It's a
general-news adaptation of a hyperlocal news bot — same engine, geography swapped for an **impact**
signal.

Topics: **frontier models & research · labs/companies · funding, M&A & business · products, tools &
agents · compute & infra · policy, safety & regulation · open source**, plus a ✨ **Pick of the Week**.

## How it works (three roles, one engine)
1. **Discover** — `run_sweeps.sh` fires six Codex web-search sweeps in parallel (one per sector),
   each hard-capped by `codex_sweep.sh` (a real SIGKILL watchdog — `perl alarm` does not kill
   `codex`). Plus official lab blogs, arXiv and crawlable outlets via WebSearch/WebFetch.
2. **Score & filter** — `scoring.py` scores each candidate on normalized 0–1 layers
   (**impact · recency · sector relevance · source reliability**), combines them by normalized
   weights, hard-gates (outside the 7-day window / unverified / duplicate), applies `min_score`
   and per-section caps. All tuning lives in `taxonomy.json`.
3. **Summarise** — `render_brief.py` puts the Pick on top, groups the rest by section, and writes
   the WhatsApp message. `state.db` (SQLite) remembers what was sent so nothing repeats week to week.

## Files
| file | role |
|---|---|
| `taxonomy.json` | the brain: sectors, sources, weights, kernels, caps, gates |
| `scoring.py` | the scored-discovery engine (`score_candidates`) |
| `render_brief.py` | compose the brief from scored candidates |
| `run_sweeps.sh` / `codex_sweep.sh` | parallel, hard-capped Codex discovery sweeps |
| `record.py` / `state.db` | deterministic weekly dedup memory (SQLite) |
| `SKILL.md` | the compose playbook the agent follows |
| `run_and_send.sh` | the weekly job: compose → hold to send time → send → record |
| `config.env.example` | copy to `config.env` (gitignored) and fill in |

## Setup
1. **whatsapp-mcp** — install the Go bridge + MCP server from
   <https://github.com/lharries/whatsapp-mcp>, scan the QR once. The bridge exposes
   `POST http://localhost:8080/api/send`.
2. **CLIs** — `claude` (Claude Code) authenticated (`claude auth login`), and `codex` (OpenAI Codex
   CLI) logged in. Both reach outlets this crawler can't.
3. **SQLite** — ships with macOS; the DB is created on first write.
4. `cp config.env.example config.env` and set `SEND_JID` (a person for beta, or a group JID),
   `ALERT_JID`, and `BOT_DIR`.
5. **Dry run:**
   ```bash
   ./run_sweeps.sh 280 2026-09-28 2026-10-05   # discover
   # build /tmp/ai-candidates.json per SKILL.md, then:
   python3 render_brief.py --json /tmp/ai-candidates.json
   ```
6. **Schedule** (macOS launchd) — load `com.<you>.ai-news.plist` to fire Mondays; the job keeps the
   Mac awake, composes, holds to the configured send time, sends, and records. A failure DMs
   `ALERT_JID` instead of failing silently.

## Design notes
- **Impact replaces geography.** The hyperlocal original ranked by distance; here the dominant
  layer is a judged 0–1 impact score, so a frontier release outranks a minor feature.
- **Parallel + capped sweeps** keep compose fast and punctual; a hung sweep can't blow the schedule.
- **Secrets stay out of git** — `config.env` and `state.db` are gitignored.

_Auto-curated from public sources. Verify before citing. Not affiliated with any outlet._
