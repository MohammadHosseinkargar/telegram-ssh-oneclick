#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/MohammadHosseinkargar/telegram-ssh-oneclick.git}"
INSTALL_DIR="/opt/telegram-ssh-oneclick"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root. Example: curl -fsSL https://raw.githubusercontent.com/MohammadHosseinkargar/telegram-ssh-oneclick/main/scripts/quick-install.sh | sudo bash"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y git
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --all --tags
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/install.sh" "$INSTALL_DIR/scripts/quick-install.sh"
exec "$INSTALL_DIR/install.sh"
