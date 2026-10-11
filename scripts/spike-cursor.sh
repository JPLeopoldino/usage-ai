#!/usr/bin/env bash
# Phase 0 spike: fetch Cursor usage using the session stored by the Cursor app.
# Never prints the token. Raw responses go to scripts/raw/ (gitignored).
set -euo pipefail

DB="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
OUT="$(cd "$(dirname "$0")" && pwd)/raw"
mkdir -p "$OUT"

JWT=$(/usr/bin/sqlite3 -readonly "file:$DB?mode=ro" \
  "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'")
if [[ -z "$JWT" ]]; then
  echo "No Cursor session found. Open Cursor and sign in." >&2
  exit 1
fi

PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2 | tr '_-' '/+')
while (( ${#PAYLOAD} % 4 )); do PAYLOAD="$PAYLOAD="; done
CLAIMS=$(printf '%s' "$PAYLOAD" | base64 -d 2>/dev/null)
SUB=$(printf '%s' "$CLAIMS" | /usr/bin/jq -r '.sub')
EXP=$(printf '%s' "$CLAIMS" | /usr/bin/jq -r '.exp')
USER_ID="${SUB##*|}"
echo "JWT exp: $(date -r "$EXP")"

COOKIE="WorkosCursorSessionToken=${USER_ID}%3A%3A${JWT}"
UA="UsageAI/0.1 (macOS)"

curl -sS -o "$OUT/cursor_usage_summary.json" -w "usage-summary: HTTP %{http_code}\n" \
  -H "Cookie: $COOKIE" -H "Accept: application/json" -A "$UA" \
  https://cursor.com/api/usage-summary

curl -sS -o "$OUT/cursor_usage_legacy.json" -w "usage (legacy): HTTP %{http_code}\n" \
  -H "Cookie: $COOKIE" -H "Accept: application/json" -A "$UA" \
  "https://cursor.com/api/usage?user=${USER_ID}"

echo "Saved to $OUT"
