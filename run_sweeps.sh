#!/bin/bash
# run_sweeps.sh [cap_seconds] "YYYY-MM-DD" "YYYY-MM-DD"  (window start, end)
# Runs all AI discovery sweeps IN PARALLEL, each hard-capped (see codex_sweep.sh), writing one
# file per sector to /tmp/ai-sweep-<name>.txt. The compose agent runs this ONCE then reads them.
#
# Why parallel + capped: codex sweeps have no native timeout and perl's SIGALRM doesn't kill codex
# (Node ignores it); a hung sweep would block 20-60 min. The SIGKILL watchdog + parallelism cap
# total wall-time at ~one sweep (~4-5 min). Each sweep is DISCOVERY ONLY — the agent still
# WebFetch-verifies dates, figures and URLs before anything reaches the brief.
HERE="$(cd "$(dirname "$0")" && pwd)"
CAP="${1:-280}"
WS="${2:-$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)}"
WE="${3:-$(date +%Y-%m-%d)}"
SW="$HERE/codex_sweep.sh"
W="from ${WS} to ${WE} (inclusive)"
cd /tmp || exit 1

$SW "$CAP" "Search the web. List the most important FRONTIER MODEL releases and AI RESEARCH breakthroughs dated ${W}. Cover new models/benchmarks/capabilities from OpenAI, Anthropic, Google DeepMind, Meta, xAI, Mistral, DeepSeek, Qwen, and major papers. For each: headline, 1-line what-happened, company, EXACT date, outlet, URL. Prefer official blogs + arXiv + Reuters/Verge/TechCrunch. Only items dated ${W}. If unsure of a date, say so. If none, say NONE." > /tmp/ai-sweep-models.txt 2>&1 &

$SW "$CAP" "Search the web. List the most important AI BUSINESS news dated ${W}: funding rounds, valuations, M&A/acquisitions, IPOs, and major enterprise deals/partnerships. For each: headline, 1-line, companies + amount, EXACT date, outlet, URL. Prefer Reuters/Bloomberg/CNBC/Crunchbase/The Information. Only items dated ${W}. If none, say NONE." > /tmp/ai-sweep-business.txt 2>&1 &

$SW "$CAP" "Search the web. List notable AI PRODUCT / TOOL / AGENT launches dated ${W}: dev tools, APIs, agent frameworks, major app/feature launches by AI companies. For each: headline, 1-line, company, EXACT date, outlet, URL. Only items dated ${W}. If none, say NONE." > /tmp/ai-sweep-products.txt 2>&1 &

$SW "$CAP" "Search the web. List AI COMPUTE / INFRASTRUCTURE news dated ${W}: chips (Nvidia, AMD, Google TPU, custom silicon), datacenters, cloud capacity, energy/power deals for AI. For each: headline, 1-line, company, EXACT date, outlet, URL. Only items dated ${W}. If none, say NONE." > /tmp/ai-sweep-infra.txt 2>&1 &

$SW "$CAP" "Search the web. List AI POLICY, REGULATION and SAFETY news dated ${W}: government action (US/EU/UK/China/India), the EU AI Act, lawsuits/investigations, safety research or incidents, governance accords. For each: headline, 1-line, who, EXACT date, outlet, URL. Prefer Reuters/TechPolicy.press/official. Only items dated ${W}. If none, say NONE." > /tmp/ai-sweep-policy.txt 2>&1 &

$SW "$CAP" "Search the web. List notable OPEN-SOURCE / OPEN-WEIGHT AI releases dated ${W}: open models and major open tooling (Llama, Mistral, DeepSeek, Qwen, Gemma, etc.) and their benchmarks. For each: headline, 1-line, who, EXACT date, outlet, URL. Only items dated ${W}. If none, say NONE." > /tmp/ai-sweep-opensource.txt 2>&1 &

wait
echo "[run_sweeps] done (window ${WS}..${WE}, cap ${CAP}s each). Files: /tmp/ai-sweep-{models,business,products,infra,policy,opensource}.txt"
for f in models business products infra policy opensource; do
  n=$(wc -l < "/tmp/ai-sweep-$f.txt" 2>/dev/null | tr -d ' '); to=""
  grep -q TIMED_OUT "/tmp/ai-sweep-$f.txt" 2>/dev/null && to=" [TIMED_OUT]"
  echo "  ai-sweep-$f.txt: ${n:-0} lines$to"
done
