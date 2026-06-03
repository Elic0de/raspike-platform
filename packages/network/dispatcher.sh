#!/usr/bin/env bash
set -euo pipefail

# NetworkManager dispatcher script.
# Run school Wi-Fi auth only when wlan0 becomes up and the SSID matches.
# Authentication failure is logged but never blocks local bridge/web services.

IFACE="${1:-}"
ACTION="${2:-}"
RASPIKE_ROOT="${RASPIKE_ROOT:-/opt/raspike}"
AUTH_ENV="$RASPIKE_ROOT/config/wifi-auth.env"
LOG_PREFIX="[raspike-dispatcher]"

log() {
  logger -t raspike-dispatcher "$*"
  printf '%s %s\n' "$LOG_PREFIX" "$*"
}

if [[ "$IFACE" != "${RASPIKE_WIFI_IFACE:-wlan0}" || "$ACTION" != "up" ]]; then
  exit 0
fi

if [[ -r "$AUTH_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$AUTH_ENV"
fi

SCHOOL_WIFI_SSID="${SCHOOL_WIFI_SSID:-}"
if [[ -z "$SCHOOL_WIFI_SSID" ]]; then
  log "SCHOOL_WIFI_SSID が未設定のため認証をスキップします"
  exit 0
fi

if ! command -v iwgetid >/dev/null 2>&1; then
  log "iwgetid が見つからないため認証をスキップします"
  exit 0
fi

CURRENT_SSID="$(iwgetid -r "$IFACE" 2>/dev/null || true)"
if [[ "$CURRENT_SSID" != "$SCHOOL_WIFI_SSID" ]]; then
  log "SSID '$CURRENT_SSID' は対象外です"
  exit 0
fi

log "学校 Wi-Fi SSID '$CURRENT_SSID' を検知しました"

if command -v systemctl >/dev/null 2>&1; then
  systemctl start raspike-network-auth.service || log "network-auth service の起動に失敗しました"
else
  "$RASPIKE_ROOT/scripts/school-auth.sh" || log "school-auth.sh が失敗しました"
fi

exit 0
