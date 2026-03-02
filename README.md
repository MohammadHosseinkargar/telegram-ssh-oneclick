# telegram-ssh-oneclick

`telegram-ssh-oneclick` is a Telegram-controlled SSH bot with a one-click installer for Debian and Ubuntu servers.

## Project Intro

This project deploys a Telegram bot that can connect to registered servers over SSH and execute commands. The installer configures dependencies, environment variables, service user, and process manager.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/MohammadHosseinkargar/telegram-ssh-oneclick/main/scripts/quick-install.sh | sudo bash
```

It clones or updates the repository in `/opt/telegram-ssh-oneclick`, runs `install.sh`, writes runtime configuration, and starts the service.

## Features

- Interactive install and reconfigure flow
- Non-interactive automation through environment variables
- `systemd` and `pm2` process manager support
- Secure `.env` generation with restrictive permissions
- Server definitions stored in JSON

## Configuration (`.env`)

Installer writes `/opt/telegram-ssh-oneclick/.env`.

Variables:

- `BOT_TOKEN` (required)
- `CHAT_ID` (required)
- `OWNER_IDS` (required, comma-separated numeric IDs)
- `PATH_PRIVATEKEY` (optional)
- `SERVERS_FILE` (optional, default `/opt/telegram-ssh-oneclick/servers.json`)
- `PROCESS_MANAGER` (`systemd` or `pm2`)
- `RECONFIGURE` (`true`/`1`)

Non-interactive example:

```bash
sudo BOT_TOKEN='123456:ABCDEF...' \
CHAT_ID='123456789' \
OWNER_IDS='123456789,987654321' \
PATH_PRIVATEKEY='/home/ubuntu/.ssh/id_rsa' \
SERVERS_FILE='/opt/telegram-ssh-oneclick/servers.json' \
PROCESS_MANAGER='systemd' \
RECONFIGURE='true' \
bash /opt/telegram-ssh-oneclick/install.sh
```

## systemd Usage

Service name: `telegram-ssh-oneclick`

```bash
sudo systemctl status telegram-ssh-oneclick
sudo systemctl restart telegram-ssh-oneclick
sudo systemctl enable telegram-ssh-oneclick
```

## Logs and Troubleshooting

Systemd logs:

```bash
journalctl -u telegram-ssh-oneclick -f
```

PM2 logs:

```bash
sudo su -s /bin/bash -c 'pm2 ls' telegram-ssh-oneclick
sudo su -s /bin/bash -c 'pm2 logs telegram-ssh-oneclick' telegram-ssh-oneclick
```

Troubleshooting checklist:

- Verify `.env` values and permissions.
- Ensure service user can read `PATH_PRIVATEKEY`.
- Validate `servers.json` syntax and ownership.
- Re-run installer if needed:

```bash
sudo bash /opt/telegram-ssh-oneclick/install.sh
```

## Persian Documentation

- [README_FA.md](README_FA.md)
