#!/usr/bin/env python3
"""Deterministic write path for state.db — weekly dedup memory.

Every item actually sent is recorded with a stable fingerprint so next week's
run won't repeat it. Idempotent (INSERT OR REPLACE).

  record.py --dry    /tmp/ai-selected.json
  record.py --commit /tmp/ai-selected.json [--week-end YYYY-MM-DD] [--dest JID] [--counts k=v,...]

selected.json = {"week_end":"YYYY-MM-DD","items":[{fp, head, url, sector, published}, ...]}
"""
import sys, os, json, sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "state.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS sent_items (
  fingerprint TEXT PRIMARY KEY, canonical_url TEXT, headline TEXT,
  sector TEXT, published_at TEXT, first_seen TEXT, last_seen TEXT, sent_week TEXT);
CREATE TABLE IF NOT EXISTS executions (
  execution_id TEXT PRIMARY KEY, run_at TEXT, window_start TEXT, window_end TEXT,
  candidates INT, dropped INT, selected INT, destination TEXT, send_result TEXT, duration_s REAL);
"""


def _conn():
    con = sqlite3.connect(DB)
    con.executescript(SCHEMA)
    return con


def _opt(flag, default=""):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("--dry", "--commit"):
        print(__doc__); return 1
    mode, path = sys.argv[1], sys.argv[2]
    obj = json.load(open(path))
    week = _opt("--week-end", obj.get("week_end", ""))
    dest = _opt("--dest", "")
    counts = dict(kv.split("=", 1) for kv in _opt("--counts").split(",") if "=" in kv)

    rows = [(it["fp"], it.get("url", ""), it.get("head", ""), it.get("sector", ""),
             it.get("published", ""), week, week, week) for it in obj["items"]]
    exec_row = (f"ai-news-{week}", week, counts.get("window_start", ""), week,
                int(counts.get("candidates", 0)), int(counts.get("dropped", 0)),
                len(rows), dest, "SUCCESS", float(counts.get("duration_s", 0)))

    if mode == "--dry":
        print(f"WOULD WRITE — execution ai-news-{week}  selected={len(rows)}")
        for r in rows:
            print(f"  sent_items: {r[0]}")
        return 0

    con = _conn(); cur = con.cursor()
    cur.execute("INSERT OR REPLACE INTO executions VALUES (?,?,?,?,?,?,?,?,?,?)", exec_row)
    cur.executemany("INSERT OR REPLACE INTO sent_items VALUES (?,?,?,?,?,?,?,?)", rows)
    con.commit(); con.close()
    print(f"COMMITTED — execution ai-news-{week} + {len(rows)} sent_items rows.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
