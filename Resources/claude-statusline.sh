#!/bin/bash
# Usage AI bridge for the Claude Code status line.
#
# Claude Code runs this after each response and passes session JSON on stdin. For Pro and Max
# subscribers that JSON includes `rate_limits` (5-hour and 7-day windows). This script saves that
# part for the Usage AI menu bar app, then prints the output of your previous status line command
# (or nothing, if you had none), so your status line looks the same as before.
#
# Installed and removed from Usage AI › Settings › Accounts › Claude.

umask 077
input=$(cat)
dir="$HOME/Library/Application Support/UsageAI"
out="$dir/claude-rate-limits.json"
next="$dir/statusline-next-command"

jq_bin=/usr/bin/jq
[ -x "$jq_bin" ] || jq_bin=$(command -v jq 2>/dev/null)

save() {
  mkdir -p "$dir"
  tmp="$dir/.claude-rate-limits.$$"
  printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$out"
}

if [ -n "$jq_bin" ]; then
  data=$(printf '%s' "$input" | "$jq_bin" -c '
    select(.rate_limits.five_hour != null or .rate_limits.seven_day != null)
    | {captured_at: (now | floor),
       rate_limits: {five_hour: .rate_limits.five_hour, seven_day: .rate_limits.seven_day}}
  ' 2>/dev/null)
  [ -n "$data" ] && save "$data"
elif printf '%s' "$input" | grep -q '"rate_limits"'; then
  # No jq (macOS 14): keep the whole payload; the app only reads `rate_limits` from it.
  save "$input"
fi

# With no previous status line, print nothing, so the status line stays empty.
if [ -s "$next" ]; then
  printf '%s' "$input" | /bin/sh -c "$(cat "$next")"
fi
exit 0
