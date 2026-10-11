#!/usr/bin/env bash
# Phase 0 spike: fetch OpenAI organization costs for the current month.
# Usage: OPENAI_ADMIN_KEY=sk-admin-... bash scripts/spike-openai.sh
# Never prints the key. Raw responses go to scripts/raw/ (gitignored).
set -euo pipefail

: "${OPENAI_ADMIN_KEY:?Set OPENAI_ADMIN_KEY to an Admin API key (Read-only is enough)}"

OUT="$(cd "$(dirname "$0")" && pwd)/raw"
mkdir -p "$OUT"

START=$(date -u -v1d -v0H -v0M -v0S +%s)

curl -sS -o "$OUT/openai_costs.json" -w "organization/costs: HTTP %{http_code}\n" \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -A "UsageAI/0.1 (macOS)" \
  "https://api.openai.com/v1/organization/costs?start_time=${START}&bucket_width=1d&limit=31&group_by=line_item"

echo "Saved to $OUT"
