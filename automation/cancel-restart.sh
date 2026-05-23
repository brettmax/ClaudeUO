#!/usr/bin/env bash
# Cancels every queued ClaudeUO restart job without queuing a replacement.
# Useful if you decide a push shouldn't trigger a restart cycle after all.

set -euo pipefail

QUEUE="${CLAUDEUO_AT_QUEUE:-c}"

existing="$(atq -q "$QUEUE" 2>/dev/null | awk '{print $1}' || true)"
if [[ -z "$existing" ]]; then
  echo "cancel-restart.sh: nothing scheduled in queue '$QUEUE'"
  exit 0
fi

echo "cancel-restart.sh: cancelling $(echo "$existing" | wc -w) job(s) in queue '$QUEUE'"
# shellcheck disable=SC2086
atrm $existing
