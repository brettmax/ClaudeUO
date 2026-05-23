#!/usr/bin/env bash
# Schedules the 6-hour restart countdown from "now":
#   T-6h, -5h, -4h, -3h, -2h, -1h30m, -1h, -45m, -30m, -15m, -5m  -> in-game broadcast
#   T-0                                                            -> RESTART
#
# Cancels any previously-scheduled ClaudeUO restart jobs before queuing a new
# round, so a fresh push to main always wins. (User-confirmed behavior:
# "GitHub Actions on push to main, timer resets on new push.")
#
# Implementation: each broadcast / restart is queued as a separate `at` job
# tagged with the queue letter 'c'. `atq -q c` enumerates them; `atrm` cancels.
#
# Env:
#   CLAUDEUO_ROOT         (optional)  Path to this repo on the server. Defaults to /opt/claudeuo.
#   CLAUDEUO_AT_QUEUE     (optional)  Single letter, default 'c'. Pick a unique queue if you
#                                     share the host with other `at` users.

set -euo pipefail

ROOT="${CLAUDEUO_ROOT:-/opt/claudeuo}"
QUEUE="${CLAUDEUO_AT_QUEUE:-c}"
BROADCAST="${ROOT}/automation/broadcast.sh"
RESTART_NOW="${ROOT}/automation/restart-now.sh"

if ! command -v at >/dev/null 2>&1; then
  echo "schedule-restart.sh: \`at\` is not installed. Install with: apt-get install -y at && systemctl enable --now atd" >&2
  exit 127
fi

if [[ ! -x "$BROADCAST" || ! -x "$RESTART_NOW" ]]; then
  echo "schedule-restart.sh: $BROADCAST and $RESTART_NOW must exist and be executable" >&2
  exit 1
fi

# Cancel any in-flight scheduled jobs in our queue. atq output is "<id>\t<time>...".
# We harvest the ids and `atrm` them. Empty queue is a no-op.
existing="$(atq -q "$QUEUE" 2>/dev/null | awk '{print $1}' || true)"
if [[ -n "$existing" ]]; then
  echo "schedule-restart.sh: cancelling in-flight jobs: $(echo "$existing" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  atrm $existing
fi

queue_at() {
  # queue_at <minutes_from_now> <shell-command-string> <label-for-logs>
  local mins="$1" cmd="$2" label="$3"
  # `at now + N minutes` is the portable spelling and resolves at queue time on the host
  # clock; we don't have to do timezone arithmetic ourselves.
  echo "$cmd" | at -q "$QUEUE" now + "$mins" minutes 2>/dev/null
  echo "  +${mins}m  ${label}"
}

# Broadcast schedule. Times are minutes from "now" (= time of push to main).
# Restart fires at +360 minutes; everything before is an in-game broadcast.
echo "schedule-restart.sh: queuing 6-hour restart countdown (queue '$QUEUE')"

# T-6h to T-2h: hourly. Broadcast counts down toward zero so we offset from total.
queue_at   0 "$BROADCAST 'The server will restart in 6 hours.'"  "T-6h announcement"
queue_at  60 "$BROADCAST 'The server will restart in 5 hours.'"  "T-5h"
queue_at 120 "$BROADCAST 'The server will restart in 4 hours.'"  "T-4h"
queue_at 180 "$BROADCAST 'The server will restart in 3 hours.'"  "T-3h"
queue_at 240 "$BROADCAST 'The server will restart in 2 hours.'"  "T-2h"

# T-2h .. T-1h: every 30 minutes. (T-2h already queued above; next is T-1h30m.)
queue_at 270 "$BROADCAST 'The server will restart in 90 minutes.'" "T-1h30m"
queue_at 300 "$BROADCAST 'The server will restart in 1 hour.'"     "T-1h"

# Last hour: every 15 minutes, with the final announcement at T-5m (skipping T-0).
queue_at 315 "$BROADCAST 'The server will restart in 45 minutes.'" "T-45m"
queue_at 330 "$BROADCAST 'The server will restart in 30 minutes.'" "T-30m"
queue_at 345 "$BROADCAST 'The server will restart in 15 minutes.'" "T-15m"
queue_at 355 "$BROADCAST 'The server will restart in 5 minutes. Please log out safely.'" "T-5m (final)"

# T-0: the actual restart trigger.
queue_at 360 "$RESTART_NOW" "RESTART"

echo "schedule-restart.sh: countdown queued. Inspect with: atq -q $QUEUE"
