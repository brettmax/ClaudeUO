#!/usr/bin/env bash
# Tells the running ModernUO process to shut down + restart immediately.
# The host's systemd unit (deploy/modernuo.service) brings it back up.

set -euo pipefail

host="${CLAUDEUO_ADMIN_HOST:-127.0.0.1}"
port="${CLAUDEUO_ADMIN_PORT:-2595}"

exec 3<>"/dev/tcp/${host}/${port}"
printf 'RESTART\n' >&3
IFS= read -r reply <&3 || reply="(no reply)"
exec 3<&-
exec 3>&-

echo "restart-now.sh: $reply"
case "$reply" in
  OK*) ;;
  *) exit 1 ;;
esac
