#!/usr/bin/env python3
"""Scored discovery engine for the weekly AI-news brief.

Same shape as the hyperlocal Garodia engine: each candidate is scored on
normalized 0-1 layers, combined by normalized weights, then ranked within its
signal_type and capped. The difference: there is no geography. The "does this
matter" signal is an IMPACT layer (0-1, judged at discovery) instead of
proximity. Hard gates zero a candidate before ranking. All tuning lives in
taxonomy.json — never in code.

  scoring.py --demo
  (importable: score_candidates(candidates, asof) -> (ranked per signal_type, dropped))
"""
import json, os, sys, datetime as dt

HERE = os.path.dirname(os.path.abspath(__file__))
TAX = json.load(open(os.path.join(HERE, "taxonomy.json")))
UTC = dt.timezone.utc


def _parse(ts):
    """Parse an ISO timestamp; treat a bare date as midnight UTC."""
    if not ts:
        return None
    try:
        d = dt.datetime.fromisoformat(ts)
    except ValueError:
        d = dt.datetime.fromisoformat(ts[:10])
    return d if d.tzinfo else d.replace(tzinfo=UTC)


def k_recency(age_h, window_h):
    """linear decay: 1.0 at age 0 -> 0.0 at window_h. Future-dated items clamp to fresh."""
    if age_h is None:
        return 0.0
    if age_h < 0:
        return 1.0
    if age_h > window_h:
        return 0.0
    return 1.0 - (age_h / window_h)


def _norm_weights():
    w = TAX["weights"]
    keys = ["impact", "recency", "sector_relevance", "source_reliability"]
    tot = sum(w[k] for k in keys)
    return {k: w[k] / tot for k in keys}


def score_one(c, asof):
    """c: {sector, source, impact (0-1), published (ISO)} + render fields.
    Returns (composite 0-1, layer breakdown, gate_reason or None)."""
    sec = TAX["sectors"][c["sector"]]
    src = TAX["sources"].get(c.get("source", "other"), TAX["sources"]["other"])
    window = sec["recency_window_h"]

    t = _parse(c.get("published"))
    age_h = (asof - t).total_seconds() / 3600.0 if t else None

    layers = {
        "impact":             float(c.get("impact", 0.0)),
        "recency":            k_recency(age_h, window),
        "sector_relevance":   sec["resident_weight"],
        "source_reliability": src["reliability"],
    }

    if not c.get("timestamp_verified", True):
        return 0.0, layers, "EXCLUDED_TIMESTAMP_UNVERIFIED"
    if layers["recency"] == 0.0:
        return 0.0, layers, "EXCLUDED_OUTSIDE_WINDOW"
    if c.get("duplicate"):
        return 0.0, layers, "EXCLUDED_DUPLICATE"

    W = _norm_weights()
    composite = sum(W[k] * layers[k] for k in W)
    return composite, layers, None


def score_candidates(candidates, asof):
    """Score all, group by signal_type, rank, apply min_score + caps."""
    out = {st: [] for st in TAX["signal_types"]}
    dropped = []
    floor = TAX.get("min_score", 0.0)
    for c in candidates:
        comp, layers, gate = score_one(c, asof)
        st = TAX["sectors"][c["sector"]]["signal_type"]
        rec = {**c, "score": round(comp, 4),
               "layers": {k: round(v, 3) for k, v in layers.items()}, "gate": gate}
        if gate:
            dropped.append(rec)
        elif comp < floor:
            rec["gate"] = f"BELOW_MIN_SCORE_{floor}"
            dropped.append(rec)
        else:
            out[st].append(rec)
    for st, cfg in TAX["signal_types"].items():
        out[st].sort(key=lambda r: r["score"], reverse=True)
        out[st] = out[st][:cfg["cap"]]
    return out, dropped


# ---- demo: a handful of synthetic candidates ----
DEMO = [
    {"sector": "pick", "source": "cnbc", "impact": 1.0, "published": "2026-09-29T18:00:00+00:00",
     "head": "OpenAI DevDay drops 'Dots' always-on agents"},
    {"sector": "models", "source": "google_blog", "impact": 0.9, "published": "2026-09-30T15:00:00+00:00",
     "head": "Google unveils Gemini 4 Argon"},
    {"sector": "policy", "source": "techpolicy_press", "impact": 0.85, "published": "2026-09-29T20:00:00+00:00",
     "head": "White House frontier-safety accord signed"},
    {"sector": "business", "source": "crunchbase", "impact": 0.6, "published": "2026-10-02T12:00:00+00:00",
     "head": "Q3 AI funding report"},
    {"sector": "models", "source": "roundup_blog", "impact": 0.3, "published": "2025-10-01T00:00:00+00:00",
     "head": "year-old item (should gate on window)"},
]


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--demo":
        asof = _parse("2026-10-05T08:00:00+00:00")
        ranked, dropped = score_candidates(DEMO, asof)
        for st in TAX["signal_types"]:
            for r in ranked[st]:
                L = r["layers"]
                print(f"  {r['score']:.3f} [{st:<10}] {r['head'][:46]}  "
                      f"(imp={L['impact']} rec={L['recency']} src={L['source_reliability']})")
        for r in dropped:
            print(f"  DROP {r['gate']:<26} {r.get('head','')[:40]}")
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
