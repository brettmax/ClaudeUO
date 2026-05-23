#!/usr/bin/env bash
# Builds ModernUO + the ClaudeUO shard overlay into /opt/claudeuo/server/Distribution.
# Idempotent. Safe to run from update-server.sh or by hand.
#
# Run as the 'claudeuo' service user.

set -euo pipefail

ROOT="${CLAUDEUO_ROOT:-/opt/claudeuo}"
cd "$ROOT"

echo "==> Building ModernUO (Release)"
dotnet build "$ROOT/server/ModernUO.slnx" -c Release

echo "==> Building ClaudeUO.Admin overlay assembly"
dotnet build "$ROOT/shard/ClaudeUO.Admin/ClaudeUO.Admin.csproj" -c Release

echo "==> Applying Distribution overlay (assemblies.json etc.)"
cp -av "$ROOT/shard/Distribution-overlay/." "$ROOT/server/Distribution/"

echo "==> Build complete."
ls -l "$ROOT/server/Distribution/ClaudeUO.Admin.dll" "$ROOT/server/Distribution/ModernUO.dll" 2>/dev/null || true
