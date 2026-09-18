#!/usr/bin/env bash
set -Eeuo pipefail

BRIDGE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$BRIDGE_DIR/data/config.json"
CONFIG_EXAMPLE="$BRIDGE_DIR/data/config.example.json"
PLIST_LABEL="id.sadesa.pos-print-bridge"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
LOG_DIR="$BRIDGE_DIR/data/logs"

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }
command -v node >/dev/null 2>&1 || fail 'Node.js 22 atau yang lebih baru belum terpasang. Instal dari https://nodejs.org/ lalu ulangi script ini.'
command -v npm >/dev/null 2>&1 || fail 'npm tidak ditemukan. Pastikan instalasi Node.js menambahkan npm ke PATH.'
NODE_BIN="$(command -v node)"

mkdir -p "$BRIDGE_DIR/data" "$LOG_DIR" "$(dirname -- "$PLIST_PATH")"
if [[ ! -f "$CONFIG_PATH" ]]; then
  cp "$CONFIG_EXAMPLE" "$CONFIG_PATH"
  printf 'Konfigurasi awal dibuat: %s\n' "$CONFIG_PATH"
  printf 'Edit host/port/path dan tandai satu printer dengan isDefault=true sebelum mencetak.\n'
fi

(cd "$BRIDGE_DIR" && npm install --omit=dev)

escape_xml() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}
NODE_XML="$(escape_xml "$NODE_BIN")"
SERVER_XML="$(escape_xml "$BRIDGE_DIR/src/server.mjs")"
WORKDIR_XML="$(escape_xml "$BRIDGE_DIR")"
OUT_XML="$(escape_xml "$LOG_DIR/bridge.out.log")"
ERR_XML="$(escape_xml "$LOG_DIR/bridge.err.log")"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$NODE_XML</string><string>$SERVER_XML</string></array>
  <key>WorkingDirectory</key><string>$WORKDIR_XML</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$OUT_XML</string>
  <key>StandardErrorPath</key><string>$ERR_XML</string>
  <key>EnvironmentVariables</key>
  <dict><key>NODE_ENV</key><string>production</string></dict>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$PLIST_LABEL"
launchctl kickstart -k "gui/$(id -u)/$PLIST_LABEL"

printf '\nPrint Bridge macOS aktif.\n'
printf 'Health check: curl http://127.0.0.1:18181/health\n'
printf 'Konfigurasi: %s\n' "$CONFIG_PATH"
printf 'Service: %s\n' "$PLIST_PATH"
printf 'Log: %s\n' "$LOG_DIR"
printf 'Buka POS > Pengaturan > Printer lalu jalankan Test Print.\n'
