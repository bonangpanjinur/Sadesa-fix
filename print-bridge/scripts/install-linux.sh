#!/usr/bin/env bash
set -Eeuo pipefail

BRIDGE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$BRIDGE_DIR/data/config.json"
CONFIG_EXAMPLE="$BRIDGE_DIR/data/config.example.json"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_NAME="sadesa-pos-print-bridge.service"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }
command -v node >/dev/null 2>&1 || fail 'Node.js 22 atau yang lebih baru belum terpasang. Instal dari https://nodejs.org/ lalu ulangi script ini.'
command -v npm >/dev/null 2>&1 || fail 'npm tidak ditemukan. Pastikan instalasi Node.js menambahkan npm ke PATH.'
NODE_BIN="$(command -v node)"

mkdir -p "$BRIDGE_DIR/data" "$UNIT_DIR"
if [[ ! -f "$CONFIG_PATH" ]]; then
  cp "$CONFIG_EXAMPLE" "$CONFIG_PATH"
  printf 'Konfigurasi awal dibuat: %s\n' "$CONFIG_PATH"
  printf 'Edit host/port/path dan tandai satu printer dengan isDefault=true sebelum mencetak.\n'
fi

(cd "$BRIDGE_DIR" && npm install --omit=dev)

cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=SaDesa POS Print Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$BRIDGE_DIR
ExecStart=$NODE_BIN $BRIDGE_DIR/src/server.mjs
Restart=on-failure
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
UNIT

if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
  printf '\nUnit dibuat di %s, tetapi systemd user tidak tersedia pada sesi ini.\n' "$UNIT_PATH"
  printf 'Aktifkan manual dengan: systemctl --user daemon-reload && systemctl --user enable --now %s\n' "$UNIT_NAME"
  exit 0
fi

systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"

printf '\nPrint Bridge Linux aktif.\n'
printf 'Health check: curl http://127.0.0.1:18181/health\n'
printf 'Konfigurasi: %s\n' "$CONFIG_PATH"
printf 'Unit: %s\n' "$UNIT_PATH"
printf 'Log: journalctl --user -u %s -f\n' "$UNIT_NAME"
printf 'Buka POS > Pengaturan > Printer lalu jalankan Test Print.\n'
