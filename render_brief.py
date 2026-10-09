#!/usr/bin/env python3
"""Compose the weekly AI brief from scored candidates.

  render_brief.py --json /tmp/ai-candidates.json   # live path
  render_brief.py --demo                            # structure check (no network)

Input JSON: {"week_start":"YYYY-MM-DD","week_end":"YYYY-MM-DD","asof":"<ISO>",
             "candidates":[ {sector, source, impact, published, head, body, src, url}, ... ]}
The composer ranks + caps via scoring.py, renders Pick of the Week on top, then
each section in order, and writes /tmp/ai-message.txt + /tmp/ai-selected.json.
No hand-ranking — edit taxonomy.json to retune.
"""
import sys, json, os, re, datetime as dt
import scoring
from scoring import TAX

HERE = os.path.dirname(os.path.abspath(__file__))
SECTION_ORDER = ["mena", "models", "business", "products", "infra", "policy", "opensource"]
MSG = "/tmp/ai-message.txt"
SEL = "/tmp/ai-selected.json"


def _slug(s):
    return re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")[:60]


def _good_url(u):
    return bool(u) and u.startswith("http") and "..." not in u and u not in ("<url>", "")


def _search_link(head, src=""):
    import urllib.parse as up
    return "https://www.google.com/search?q=" + up.quote(f"{head} {src}".strip())


def _line(r):
    head = r.get("head", "")
    body = r.get("body", "")
    out = [f"• *{head}*" + (f" {body}" if body else "")]
    url = r.get("url") if _good_url(r.get("url")) else None
    src = r.get("src", "")
    if url:
        out.append(f"  {url}")
    elif src:
        out.append(f"  _{src}_")
    return out


def compose(week_start, week_end, ranked):
    ws = dt.date.fromisoformat(week_start).strftime("%-d %b")
    we = dt.date.fromisoformat(week_end).strftime("%-d %b %Y")
    L = ["🤖 *AI WEEKLY* — the week in AI", f"🗓 {ws} – {we}", ""]

    for r in ranked.get("pick", []):
        L.append("✨ *PICK OF THE WEEK*")
        L += _line(r)
        L.append("")

    for st in SECTION_ORDER:
        items = ranked.get(st, [])
        if not items:
            continue
        sec = TAX["sectors"][st]
        L.append(f"{sec['emoji']} *{sec['title']}*")
        for r in items:
            L += _line(r)
        L.append("")

    L.append("━" * 10)
    L.append("_Weekly AI brief · auto-curated from public sources · verify before citing._")
    return "\n".join(L)


def emit_selected(week_end, ranked):
    items = []
    for st in TAX["signal_types"]:
        for r in ranked.get(st, []):
            base = (r.get("published") or "")[:10]
            fp = r.get("fp") or f"{r['sector']}|{_slug(r.get('head'))}|{base}"
            items.append({"fp": fp, "sector": r["sector"], "head": r.get("head"),
                          "url": r.get("url", ""), "src": r.get("src", ""),
                          "published": r.get("published", "")})
    json.dump({"week_end": week_end, "items": items}, open(SEL, "w"), indent=2)


def render_from_json(path):
    obj = json.load(open(path)) if path != "-" else json.load(sys.stdin)
    week_start, week_end = obj["week_start"], obj["week_end"]
    asof = scoring._parse(obj.get("asof") or f"{week_end}T08:00:00+04:00")
    ranked, dropped = scoring.score_candidates(obj["candidates"], asof)
    emit_selected(week_end, ranked)
    msg = compose(week_start, week_end, ranked)
    open(MSG, "w").write(msg)
    print(msg)
    print(f"\n--- scoring trace ({week_start} -> {week_end}) ---")
    for st in TAX["signal_types"]:
        for r in ranked[st]:
            print(f"  {r['score']:.3f} [{st:<10}] {r.get('head','')[:46]}")
    for r in dropped:
        print(f"  DROP {r['gate']:<26} {r.get('head','')[:40]}")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--json":
        render_from_json(sys.argv[2] if len(sys.argv) > 2 else "-")
        return
    if len(sys.argv) > 1 and sys.argv[1] == "--demo":
        asof = scoring._parse("2026-10-05T08:00:00+00:00")
        ranked, _ = scoring.score_candidates(scoring.DEMO, asof)
        print(compose("2026-09-28", "2026-10-05", ranked))
        return
    print(__doc__)


if __name__ == "__main__":
    main()
