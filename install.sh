#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/telegram-ssh-oneclick"
SERVICE_USER="telegram-ssh-oneclick"
SERVICE_NAME="telegram-ssh-oneclick"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DEFAULT_SERVERS_FILE="${INSTALL_DIR}/servers.json"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PM_CHOICE="${PROCESS_MANAGER:-}"
RECONFIGURE="${RECONFIGURE:-}"

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Please run as root (example: sudo bash install.sh)."
    exit 1
  fi
}

is_interactive() {
  [[ -t 0 && -t 1 ]]
}

log() {
  echo "[install] $*"
}

warn() {
  echo "[warn] $*"
}

fail() {
  echo "[error] $*" >&2
  exit 1
}

require_supported_os() {
  [[ -f /etc/os-release ]] || fail "Cannot detect OS. /etc/os-release is missing."

  # shellcheck disable=SC1091
  source /etc/os-release
  local major="${VERSION_ID%%.*}"

  case "${ID:-}" in
    ubuntu)
      (( major >= 20 )) || fail "Ubuntu 20.04+ is required."
      ;;
    debian)
      (( major >= 11 )) || fail "Debian 11+ is required."
      ;;
    *)
      fail "Unsupported OS: ${ID:-unknown}. Supported: Ubuntu 20.04+, Debian 11+."
      ;;
  esac
}

apt_install_if_missing() {
  local update_needed=0
  local pkg

  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      update_needed=1
      break
    fi
  done

  if (( update_needed == 1 )); then
    log "Installing required packages: $*"
    apt-get update -y
    apt-get install -y "$@"
  fi
}

ensure_prerequisites() {
  apt_install_if_missing git curl ca-certificates openssh-client

  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    log "Node.js/npm not found. Installing Node.js LTS from NodeSource."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
  fi
}

ensure_service_user() {
  local nologin_bin
  nologin_bin="$(command -v nologin || true)"
  [[ -n "$nologin_bin" ]] || nologin_bin="/usr/sbin/nologin"

  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    log "Service user '$SERVICE_USER' already exists."
  else
    log "Creating service user '$SERVICE_USER'."
    useradd --system --home "$INSTALL_DIR" --create-home --shell "$nologin_bin" "$SERVICE_USER"
  fi
}

sync_project_files() {
  mkdir -p "$INSTALL_DIR"

  if [[ "$SCRIPT_DIR" == "$INSTALL_DIR" ]]; then
    log "Using existing project in $INSTALL_DIR"
  else
    log "Syncing project files to $INSTALL_DIR"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude ".git" \
        --exclude "node_modules" \
        --exclude ".env" \
        --exclude "servers.json" \
        "$SCRIPT_DIR/" "$INSTALL_DIR/"
    else
      tar -C "$SCRIPT_DIR" \
        --exclude=".git" \
        --exclude="node_modules" \
        --exclude=".env" \
        --exclude="servers.json" \
        -cf - . | tar -C "$INSTALL_DIR" -xf -
    fi
  fi

  chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
}

read_visible() {
  local prompt="$1"
  local default="${2:-}"
  local value=""

  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
  else
    read -r -p "$prompt: " value
    echo "$value"
  fi
}

read_secret() {
  local prompt="$1"
  local value=""
  read -r -s -p "$prompt: " value
  echo
  echo "$value"
}

validate_bot_token() {
  [[ "$1" =~ ^[0-9]{6,}:[A-Za-z0-9_-]{20,}$ ]]
}

validate_id_list() {
  [[ "$1" =~ ^-?[0-9]+(,-?[0-9]+)*$ ]]
}

owner_home() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    echo "/root"
  fi
}

load_existing_env() {
  local env_file="$INSTALL_DIR/.env"

  if [[ -f "$env_file" ]]; then
    EXISTING_BOT_TOKEN="$(sed -n 's/^BOT_TOKEN=//p' "$env_file" | tail -n1)"
    EXISTING_CHAT_ID="$(sed -n 's/^CHAT_ID=//p' "$env_file" | tail -n1)"
    EXISTING_OWNER_IDS="$(sed -n 's/^OWNER_IDS=//p' "$env_file" | tail -n1)"
    EXISTING_PATH_PRIVATEKEY="$(sed -n 's/^PATH_PRIVATEKEY=//p' "$env_file" | tail -n1)"
    EXISTING_SERVERS_FILE="$(sed -n 's/^SERVERS_FILE=//p' "$env_file" | tail -n1)"
    log "Existing configuration found at $env_file"
  fi
}

confirm_reconfigure_if_needed() {
  local marker="$INSTALL_DIR/.env"

  if [[ -f "$marker" ]]; then
    if [[ "$RECONFIGURE" == "1" || "$RECONFIGURE" == "true" ]]; then
      return
    fi

    if ! is_interactive; then
      log "Non-interactive mode detected: reusing/updating existing configuration."
      return
    fi

    local ans
    ans="$(read_visible "Existing install detected. Reconfigure now? (y/n)" "y")"
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      log "Keeping current configuration."
      exit 0
    fi
  fi
}

ask_bot_token() {
  local existing="${EXISTING_BOT_TOKEN:-}"

  if [[ -n "${BOT_TOKEN:-}" ]]; then
    validate_bot_token "$BOT_TOKEN" || fail "Invalid BOT_TOKEN format."
    return
  fi

  while true; do
    if is_interactive; then
      if [[ -n "$existing" ]]; then
        local use_existing
        use_existing="$(read_visible "Step B - Keep existing bot token? (y/n)" "y")"
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
          BOT_TOKEN="$existing"
        else
          BOT_TOKEN="$(read_secret "Step B - Telegram bot token")"
        fi
      else
        BOT_TOKEN="$(read_secret "Step B - Telegram bot token")"
      fi
    elif [[ -n "$existing" ]]; then
      BOT_TOKEN="$existing"
    else
      fail "BOT_TOKEN is required in non-interactive mode."
    fi

    # Normalize pasted token to avoid hidden whitespace/CRLF issues.
    BOT_TOKEN="$(printf '%s' "$BOT_TOKEN" | tr -d '[:space:]')"

    if validate_bot_token "$BOT_TOKEN"; then
      break
    fi

    warn "Invalid bot token format. Expected like 123456:ABC..."
    existing=""
  done
}

ask_chat_id() {
  local existing="${EXISTING_CHAT_ID:-}"

  if [[ -n "${CHAT_ID:-}" ]]; then
    [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]] || fail "CHAT_ID must be numeric."
    return
  fi

  while true; do
    if is_interactive; then
      CHAT_ID="$(read_visible "Step C - Telegram chat_id" "$existing")"
    elif [[ -n "$existing" ]]; then
      CHAT_ID="$existing"
    else
      fail "CHAT_ID is required in non-interactive mode."
    fi

    if [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
      break
    fi

    warn "CHAT_ID must be numeric."
    existing=""
  done
}

ask_owner_ids() {
  local existing="${EXISTING_OWNER_IDS:-}"

  if [[ -n "${OWNER_IDS:-}" ]]; then
    validate_id_list "$OWNER_IDS" || fail "OWNER_IDS must be numeric/comma-separated."
    return
  fi

  while true; do
    if is_interactive; then
      OWNER_IDS="$(read_visible "Step D - owner_ids (comma-separated)" "$existing")"
    elif [[ -n "$existing" ]]; then
      OWNER_IDS="$existing"
    else
      fail "OWNER_IDS is required in non-interactive mode."
    fi

    if validate_id_list "$OWNER_IDS"; then
      break
    fi

    warn "OWNER_IDS must be numeric/comma-separated (example: 123,456,-100789)."
    existing=""
  done
}

generate_ssh_key() {
  local key_path="$1"
  local key_dir
  key_dir="$(dirname "$key_path")"

  mkdir -p "$key_dir"
  chmod 700 "$key_dir"
  ssh-keygen -t rsa -b 4096 -f "$key_path" -N ""

  if [[ -f "${key_path}.pub" ]]; then
    echo
    log "Add this public key to your remote server(s):"
    cat "${key_path}.pub"
    echo
  fi
}

ask_private_key_path() {
  local operator_home
  operator_home="$(owner_home)"
  local default_key="${operator_home}/.ssh/id_rsa"
  local existing="${EXISTING_PATH_PRIVATEKEY:-$default_key}"

  if [[ -n "${PATH_PRIVATEKEY:-}" ]]; then
    [[ -f "$PATH_PRIVATEKEY" ]] || fail "PATH_PRIVATEKEY not found: $PATH_PRIVATEKEY"
    return
  fi

  while true; do
    if is_interactive; then
      PATH_PRIVATEKEY="$(read_visible "Step E - SSH private key path" "$existing")"
    else
      PATH_PRIVATEKEY="$existing"
    fi

    [[ -n "$PATH_PRIVATEKEY" ]] || PATH_PRIVATEKEY="$default_key"

    if [[ -f "$PATH_PRIVATEKEY" ]]; then
      break
    fi

    if is_interactive; then
      local gen
      gen="$(read_visible "Key not found. Generate keypair at $PATH_PRIVATEKEY? (y/n)" "y")"
      if [[ "$gen" =~ ^[Yy]$ ]]; then
        generate_ssh_key "$PATH_PRIVATEKEY"
        break
      fi
    else
      fail "PATH_PRIVATEKEY not found: $PATH_PRIVATEKEY"
    fi

    existing="$default_key"
  done
}

ask_servers_file() {
  local existing="${SERVERS_FILE:-${EXISTING_SERVERS_FILE:-$DEFAULT_SERVERS_FILE}}"

  if is_interactive; then
    SERVERS_FILE="$(read_visible "Step F - servers file path" "$existing")"
  else
    SERVERS_FILE="$existing"
  fi

  [[ -n "$SERVERS_FILE" ]] || SERVERS_FILE="$DEFAULT_SERVERS_FILE"
  mkdir -p "$(dirname "$SERVERS_FILE")"

  if [[ ! -f "$SERVERS_FILE" ]]; then
    log "Creating servers template at $SERVERS_FILE"
    cat >"$SERVERS_FILE" <<'JSON'
[
  {
    "host": "example.com",
    "username": "root",
    "port": "22",
    "password": "",
    "pathPrivateKey": "/path/to/private/key",
    "keypass": "",
    "note": "sample"
  }
]
JSON
  fi
}

ask_process_manager() {
  if [[ -n "$PM_CHOICE" ]]; then
    case "$PM_CHOICE" in
      systemd|pm2)
        return
        ;;
      *)
        warn "Invalid PROCESS_MANAGER='$PM_CHOICE'. Falling back to systemd."
        PM_CHOICE="systemd"
        ;;
    esac
  else
    PM_CHOICE="systemd"
  fi

  if is_interactive && [[ -z "${PROCESS_MANAGER:-}" ]]; then
    local ans
    ans="$(read_visible "Step G - process manager (systemd/pm2)" "$PM_CHOICE")"
    case "$ans" in
      pm2|PM2)
        PM_CHOICE="pm2"
        ;;
      *)
        PM_CHOICE="systemd"
        ;;
    esac
  fi
}

write_env_file() {
  local env_file="$INSTALL_DIR/.env"

  umask 077
  cat >"$env_file" <<EOF
BOT_TOKEN=$BOT_TOKEN
CHAT_ID=$CHAT_ID
OWNER_IDS=$OWNER_IDS
PATH_PRIVATEKEY=$PATH_PRIVATEKEY
SERVERS_FILE=$SERVERS_FILE
EOF

  chown "$SERVICE_USER":"$SERVICE_USER" "$env_file"
  chmod 600 "$env_file"

  chown "$SERVICE_USER":"$SERVICE_USER" "$SERVERS_FILE"
  chmod 600 "$SERVERS_FILE"
}

check_private_key_readability() {
  if ! su -s /bin/sh -c "test -r \"$PATH_PRIVATEKEY\"" "$SERVICE_USER"; then
    warn "Service user '$SERVICE_USER' cannot read PATH_PRIVATEKEY: $PATH_PRIVATEKEY"
    warn "Suggested fix: chown $SERVICE_USER:$SERVICE_USER $PATH_PRIVATEKEY"
    warn "Or: chmod 640 $PATH_PRIVATEKEY and ensure group access."
  fi
}

install_node_deps() {
  log "Installing npm dependencies in $INSTALL_DIR"
  if [[ -f "$INSTALL_DIR/package-lock.json" ]]; then
    (cd "$INSTALL_DIR" && npm ci --omit=dev)
  else
    (cd "$INSTALL_DIR" && npm install --omit=dev)
  fi

  chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
}

configure_systemd() {
  log "Configuring systemd service"

  cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Telegram SSH OneClick Bot
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/env node bot.js
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"

  log "Service status:"
  systemctl --no-pager --full status "$SERVICE_NAME" || true
  echo "Logs: journalctl -u $SERVICE_NAME -f"
}

configure_pm2() {
  log "Configuring PM2 mode"

  if ! command -v pm2 >/dev/null 2>&1; then
    npm install -g pm2
  fi

  su -s /bin/bash -c "cd '$INSTALL_DIR' && pm2 describe '$SERVICE_NAME' >/dev/null 2>&1 && pm2 restart '$SERVICE_NAME' --update-env || pm2 start bot.js --name '$SERVICE_NAME' --time --update-env" "$SERVICE_USER"
  su -s /bin/bash -c "pm2 save" "$SERVICE_USER"

  if systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
    systemctl disable --now "$SERVICE_NAME" || true
  fi

  log "PM2 process list:"
  su -s /bin/bash -c "pm2 ls" "$SERVICE_USER"
  echo "Logs: su -s /bin/bash -c 'pm2 logs $SERVICE_NAME' $SERVICE_USER"
}

main() {
  need_root
  require_supported_os

  log "Step A - Checking prerequisites"
  ensure_prerequisites

  ensure_service_user
  sync_project_files
  confirm_reconfigure_if_needed
  load_existing_env

  ask_bot_token
  ask_chat_id
  ask_owner_ids
  ask_private_key_path
  ask_servers_file
  ask_process_manager

  write_env_file
  check_private_key_readability
  install_node_deps

  log "Step H - Starting service"
  if [[ "$PM_CHOICE" == "pm2" ]]; then
    configure_pm2
  else
    configure_systemd
  fi

  log "Install complete."
}

main "$@"
