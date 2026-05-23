#!/usr/bin/env bash
# Pull-and-build, then arm the restart countdown. Called by GitHub Actions on
# every push to main (via SSH) &mdash; see .github/workflows/deploy.yml.
#
# Important: this script does NOT bounce the server itself. It builds the new
# bits into Distribution/ and then schedules a restart 6 hours out. The
# scheduler will broadcast the countdown and trigger the actual restart when
# the timer fires. Running ModernUO process keeps serving players in the
# meantime.
#
# Run as the 'claudeuo' service user.

set -euo pipefail

ROOT="${CLAUDEUO_ROOT:-/opt/claudeuo}"
REF="${1:-main}"

cd "$ROOT"

echo "==> Fetching latest"
git fetch --all --prune
git checkout "$REF"
git pull --ff-only origin "$REF"
git submodule update --init --recursive

echo "==> Building"
bash "$ROOT/deploy/build.sh"

echo "==> (Re)scheduling 6-hour restart countdown"
CLAUDEUO_ROOT="$ROOT" bash "$ROOT/automation/schedule-restart.sh"

echo "==> Update complete. Next restart in ~6 hours."
