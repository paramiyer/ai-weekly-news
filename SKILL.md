---
name: ai-weekly-news-bot
description: Weekly (Monday) AI-news brief to WhatsApp. One sweep agent discovers, the scoring engine filters/ranks, the composer summarises. Topics - frontier models, labs/companies, funding/M&A, products/agents, compute/infra, policy/safety, open source.
---

# AI Weekly — build the brief (COMPOSE step)

Goal: a ranked, deduped weekly AI brief for the window **{week_start} → {week_end}** (the last 7
days, ending on the Monday run date). You discover candidates, emit them as objects, and let the
engine score + compose. **You never hand-rank or hand-format** — edit `taxonomy.json` to retune.
All paths are relative to this file's directory (`HERE`).

## 0. Window (HARD)
Only items **published inside {week_start} 00:00 → {week_end} 23:59 (UTC-ish)** qualify. A landmark
item from just before the window may be carried ONLY if there is a genuinely new development inside
it; summarise the new development. The scorer's recency kernel hard-gates anything older.

## 1. Discovery — run ALL Codex sweeps in PARALLEL, hard-capped
The seven sweeps (mena, models, business, products, infra, policy, opensource) reach the
paywalled/blocked outlets (The Information, Bloomberg, Reuters, The National, etc.). Run them with
ONE command:
```bash
HERE/run_sweeps.sh 280 {week_start} {week_end}
```
Then read `/tmp/ai-sweep-{mena,models,business,products,infra,policy,opensource}.txt`. The **mena**
sweep is the local hook for this audience (UAE/Saudi/Gulf — G42, HUMAIN, MGX, TII/Falcon, SDAIA,
sovereign AI & datacenter deals, PIF/Mubadala AI bets, regional regulation); keep it even when the
global sections are busy. **Do NOT run
`codex exec` serially or unbounded** — codex ignores perl's SIGALRM, so a hung sweep blocks 20-60
min; `run_sweeps.sh`+`codex_sweep.sh` use a real SIGKILL watchdog and run in parallel (~4-5 min
total). A NONE/TIMED_OUT file just means "no candidates this leg" — fall back to WebSearch/WebFetch.
Also sweep directly: official lab blogs (openai.com, anthropic.com, deepmind.google, ai.meta.com,
mistral.ai), arXiv, and the crawlable outlets (The Verge, TechCrunch, VentureBeat, Ars, CNBC).

## 2. Verify (HARD)
Codex output is CANDIDATES, not facts. For each item, confirm the **exact publication date** and
the key figure/claim from the source before including it. Cite a URL Codex found even if this
crawler cannot open it, PROVIDED Codex gave a specific outlet + date. Drop anything whose date you
cannot pin inside the window.

## 3. Map each candidate to a sector
`mena` · `models` · `business` · `products` · `infra` · `policy` · `opensource` — and exactly ONE
`pick` (the single highest-impact item of the week; it also opens the brief). `mena` = anything
centred on the UAE/Saudi/Gulf/Middle East (a regional company, deal, policy, or buildout), even if
it would also fit a global sector — local relevance wins. Sectors/caps are in `taxonomy.json`; the
brief renders MENA first, right after the Pick.

## 4. Set `impact` (0–1) — this replaces geography
This is the dominant layer. Judge how big a deal the item is for an AI-practitioner audience:
- **0.9–1.0** field-defining: a frontier model release, a landmark acquisition/regulation, a safety
  incident with industry-wide consequences.
- **0.6–0.8** notable: a strong model/product, a large raise, a significant policy move.
- **0.3–0.5** minor: incremental updates, small rounds, routine launches.
- **< 0.3** skip. Be stingy — the brief is 8–12 items, not a firehose.

## 5. Dedupe against state.db (weekly memory)
```bash
sqlite3 HERE/state.db "select fingerprint, headline, sent_week from sent_items order by sent_week desc limit 60;"
```
Fingerprint = `sector|slug(headline)|published-date`. If the same story (same subject) was sent in a
prior week, set `"duplicate": true` on the candidate (the scorer drops it). A genuine NEW development
on a running story is NOT a duplicate — summarise the new angle.

## 6. Build the candidate JSON
Write `/tmp/ai-candidates.json`:
```json
{"week_start":"{week_start}","week_end":"{week_end}","asof":"{week_end}T08:00:00+04:00",
 "candidates":[
   {"sector":"pick","source":"cnbc","impact":1.0,"published":"2026-09-29T18:00:00+00:00",
    "head":"OpenAI DevDay drops 'Dots' always-on agents",
    "body":"25+ announcements: Dots, GPT-6.1 Sol at ~1/5 price, Agents API beta.",
    "src":"CNBC","url":"https://..."}
 ]}
```
`source` = a key in `taxonomy.sources` (official blogs score highest; `roundup_blog`/`hacker_news`
lowest). `src` = the human label shown in the message. `published` = ISO datetime.

## 7. Score + compose (THE engine — no hand-ranking)
```bash
python3 HERE/render_brief.py --json /tmp/ai-candidates.json
```
It ranks within each sector, applies `min_score` + caps, puts the Pick on top, and writes
`/tmp/ai-message.txt` + `/tmp/ai-selected.json`. The text **above** the `--- scoring trace ---` line
IS the message. The trace is your diagnostics — report the per-item scores and every DROP line.
End with `BOT_RESULT: COMPOSED`. (The scheduled wrapper holds to the send time, sends, and records.)

## Format notes
- No personal attribution in the message. The footer is auto-generated by the composer.
- Keep each item to a bold headline + one plain line + link. 8–12 items total.
- If a whole sector has nothing in-window, omit it (no empty headers).
