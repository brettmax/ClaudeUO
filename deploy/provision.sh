#!/usr/bin/env bash
# One-shot provisioning for a fresh DigitalOcean Ubuntu 24.04 droplet that will
# run the ClaudeUO ModernUO shard. Run as root (or with sudo).
#
# What it does:
#   1. apt update + base packages (git, build deps, at, ufw)
#   2. Microsoft .NET 10 SDK (ModernUO's global.json pins 10.0.201)
#   3. Creates the 'claudeuo' service user + /opt/claudeuo workdir
#   4. Clones this repo (incl. submodules) into /opt/claudeuo
#   5. Installs + enables the systemd unit and starts atd
#   6. Opens UDP/TCP firewall holes for SSH (22) and UO (2593)
#
# The script is idempotent &mdash; re-running it is safe.
#
# Required env:
#   CLAUDEUO_REPO   git URL of this repo (e.g. git@github.com:you/ClaudeUO.git)
#
# Optional env:
#   CLAUDEUO_REF    branch/tag/ref to check out (default: main)

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "provision.sh: must run as root (use sudo)" >&2
  exit 1
fi

: "${CLAUDEUO_REPO:?must set CLAUDEUO_REPO to the git URL of this repo}"
CLAUDEUO_REF="${CLAUDEUO_REF:-main}"
INSTALL_DIR="/opt/claudeuo"
SERVICE_USER="claudeuo"

echo "==> Updating apt and installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  ca-certificates curl wget gnupg lsb-release \
  git build-essential pkg-config \
  at ufw \
  jq

echo "==> Enabling and starting atd (used by the restart scheduler)"
systemctl enable --now atd

echo "==> Installing Microsoft .NET 10 SDK"
# Use Microsoft's package repo. Ubuntu 24.04 = noble.
if ! command -v dotnet >/dev/null 2>&1 || ! dotnet --list-sdks | grep -q '^10\.'; then
  wget -q "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
  dpkg -i /tmp/packages-microsoft-prod.deb
  rm -f /tmp/packages-microsoft-prod.deb
  apt-get update -y
  apt-get install -y dotnet-sdk-10.0
fi
dotnet --list-sdks

echo "==> Creating service user '$SERVICE_USER'"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --create-home --shell /bin/bash --home-dir "/home/$SERVICE_USER" "$SERVICE_USER"
fi

echo "==> Cloning repo into $INSTALL_DIR"
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  mkdir -p "$INSTALL_DIR"
  chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
  sudo -u "$SERVICE_USER" git clone --recurse-submodules "$CLAUDEUO_REPO" "$INSTALL_DIR"
fi
sudo -u "$SERVICE_USER" git -C "$INSTALL_DIR" fetch --all --prune
sudo -u "$SERVICE_USER" git -C "$INSTALL_DIR" checkout "$CLAUDEUO_REF"
sudo -u "$SERVICE_USER" git -C "$INSTALL_DIR" submodule update --init --recursive

echo "==> Installing systemd unit"
install -m 0644 "$INSTALL_DIR/deploy/modernuo.service" /etc/systemd/system/modernuo.service
systemctl daemon-reload

echo "==> Building the shard (initial)"
sudo -u "$SERVICE_USER" bash "$INSTALL_DIR/deploy/build.sh"

echo "==> Enabling and starting modernuo.service"
systemctl enable modernuo.service
systemctl restart modernuo.service || true

echo "==> Firewall: allowing SSH (22) and UO (2593)"
ufw allow 22/tcp || true
ufw allow 2593/tcp || true
ufw --force enable || true

echo "==> Provisioning complete."
echo "    systemctl status modernuo.service"
echo "    journalctl -u modernuo.service -f"
