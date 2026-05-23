#!/usr/bin/env bash
# Sends one in-game broadcast via the ClaudeUO.Admin localhost socket.
#
# Usage: broadcast.sh "<message>" [hue]
#
# Default hue 0x35 (53) matches the existing ModernUO shutdown broadcasts.
# Host/port read from CLAUDEUO_ADMIN_HOST / CLAUDEUO_ADMIN_PORT (defaults
# 127.0.0.1 / 2595).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <message> [hue]" >&2
  exit 2
fi

msg="$1"
hue="${2:-53}"
host="${CLAUDEUO_ADMIN_HOST:-127.0.0.1}"
port="${CLAUDEUO_ADMIN_PORT:-2595}"

# Print the request, read one line of response, then close.
# Requires bash's /dev/tcp; that's available on every supported distro
# (DigitalOcean's Ubuntu 24.04 image ships bash 5.x with networking enabled).
exec 3<>"/dev/tcp/${host}/${port}"
printf 'BROADCAST %d %s\n' "$hue" "$msg" >&3
IFS= read -r reply <&3 || reply="(no reply)"
exec 3<&-
exec 3>&-

case "$reply" in
  OK*) ;;
  *)
    echo "broadcast.sh: server replied: $reply" >&2
    exit 1
    ;;
esac
