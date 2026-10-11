#!/usr/bin/env bash
# Phase 0 spike: fetch Claude subscription usage through the OAuth usage endpoint
# (the optional source). Reads the token Claude Code stores in the Keychain.
# Never prints the token. Raw responses go to scripts/raw/ (gitignored).
set -euo pipefail

OUT="$(cd "$(dirname "$0")" && pwd)/raw"
mkdir -p "$OUT"

TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w \
  | /usr/bin/jq -r '.claudeAiOauth.accessToken // empty')
if [[ -z "$TOKEN" ]]; then
  echo "No Claude Code OAuth login found. Run \`claude\` and log in." >&2
  exit 1
fi

curl -sS -o "$OUT/claude_usage.json" -w "oauth/usage: HTTP %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Accept: application/json" \
  -A "UsageAI/0.1 (macOS)" \
  https://api.anthropic.com/api/oauth/usage

echo "Saved to $OUT"
