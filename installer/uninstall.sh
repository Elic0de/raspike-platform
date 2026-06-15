#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer/lib.sh
source "$SCRIPT_DIR/lib.sh"

REMOVE_DATA="${REMOVE_DATA:-false}"

usage() {
  cat <<'USAGE'
Usage: sudo ./installer/uninstall.sh [--remove-data]

Options:
  --remove-data    /opt/raspike も削除します。指定しない場合は service 類だけ削除します。
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remove-data)
        REMOVE_DATA=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "不明なオプションです: $1"
        ;;
    esac
  done
}

remove_services() {
  log "systemd service を stop/disable します"
  systemctl_if_available disable --now raspike-bridge.service || true
  systemctl_if_available disable --now raspike-web.service || true
  systemctl_if_available disable --now raspike-network-auth.service || true
  systemctl_if_available disable --now raspike-update.service || true

  rm -f "$SYSTEMD_DIR/raspike-bridge.service"
  rm -f "$SYSTEMD_DIR/raspike-web.service"
  rm -f "$SYSTEMD_DIR/raspike-network-auth.service"
  rm -f "$SYSTEMD_DIR/raspike-update.service"
  rm -f /usr/local/bin/raspike-platform-version
}

remove_network_and_udev() {
  local serial_rule="$UDEV_RULES_DIR/99-serial.rules"
  local serial_backup="$RASPIKE_ROOT/backups/udev/99-serial.rules.original"

  log "dispatcher と udev rule を削除します"
  rm -f "$NM_DISPATCHER_DIR/90-raspike-school-auth"

  if [[ -f "$serial_backup" ]]; then
    log "install 前の 99-serial.rules を復元します: $serial_rule"
    install_file "$serial_backup" "$serial_rule" 0644 root root
  elif [[ -f "$serial_rule" ]] && grep -q "$RASPIKE_MANAGED_MARKER" "$serial_rule"; then
    log "platform 管理の 99-serial.rules を削除します"
    rm -f "$serial_rule"
  else
    log "99-serial.rules は platform 管理外のため変更しません"
  fi
}

remove_data_if_requested() {
  if [[ "$REMOVE_DATA" != "true" ]]; then
    log "$RASPIKE_ROOT は残します。削除する場合は --remove-data を指定してください"
    return
  fi

  read -r -p "$RASPIKE_ROOT を完全に削除します。よろしいですか？ [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      rm -rf "$RASPIKE_ROOT"
      log "$RASPIKE_ROOT を削除しました"
      ;;
    *)
      log "$RASPIKE_ROOT の削除をキャンセルしました"
      ;;
  esac
}

main() {
  parse_args "$@"
  require_root

  remove_services
  remove_network_and_udev

  log "systemd と udev を再読み込みします"
  systemctl_if_available daemon-reload
  udevadm control --reload-rules || warn "udev rule の reload に失敗しました"

  remove_data_if_requested
  log "アンインストール処理が完了しました"
}

main "$@"
