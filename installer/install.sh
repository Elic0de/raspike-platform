#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer/lib.sh
source "$SCRIPT_DIR/lib.sh"

BRIDGE_REPO_URL="${BRIDGE_REPO_URL:-https://github.com/Elic0de/raspike-bridge-ps5.git}"
BRIDGE_REF="${BRIDGE_REF:-main}"
WEB_RELEASE_REPO="${WEB_RELEASE_REPO:-Elic0de/raspike-web-control}"
WEB_RELEASE_ASSET="${WEB_RELEASE_ASSET:-dist.zip}"
WEB_DIST_URL="${WEB_DIST_URL:-$(github_latest_asset_url "$WEB_RELEASE_REPO" "$WEB_RELEASE_ASSET")}"

install_bridge() {
  require_command git

  if [[ -d "$RASPIKE_ROOT/apps/bridge/.git" ]]; then
    log "bridge repo は既に clone 済みです。fetch して $BRIDGE_REF に合わせます"
    git -C "$RASPIKE_ROOT/apps/bridge" fetch --all --tags --prune
    git -C "$RASPIKE_ROOT/apps/bridge" checkout "$BRIDGE_REF"
    git -C "$RASPIKE_ROOT/apps/bridge" pull --ff-only || warn "bridge の pull に失敗しました。ローカル状態を確認してください"
  else
    log "bridge repo を clone します: $BRIDGE_REPO_URL"
    rm -rf "$RASPIKE_ROOT/apps/bridge"
    git clone --branch "$BRIDGE_REF" "$BRIDGE_REPO_URL" "$RASPIKE_ROOT/apps/bridge"
  fi

  chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_ROOT/apps/bridge"
}

install_web() {
  require_command unzip
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  download_file "$WEB_DIST_URL" "$tmpdir/dist.zip"

  log "web dist.zip を展開します"
  rm -rf "$tmpdir/web"
  mkdir -p "$tmpdir/web"
  unzip -q "$tmpdir/dist.zip" -d "$tmpdir/web"

  backup_path "$RASPIKE_ROOT/apps/web"
  mkdir -p "$RASPIKE_ROOT/apps"
  mv "$tmpdir/web" "$RASPIKE_ROOT/apps/web"
  chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_ROOT/apps/web"
}

install_configs() {
  copy_config_if_missing "$REPO_ROOT/packages/config/raspike.env" "$RASPIKE_ROOT/config/raspike.env" 0644
  copy_config_if_missing "$REPO_ROOT/packages/config/wifi-auth.example.env" "$RASPIKE_ROOT/config/wifi-auth.env" 0600
}

install_systemd() {
  log "systemd service を配置します"
  install_file "$REPO_ROOT/packages/systemd/raspike-bridge.service" "$SYSTEMD_DIR/raspike-bridge.service" 0644
  install_file "$REPO_ROOT/packages/systemd/raspike-web.service" "$SYSTEMD_DIR/raspike-web.service" 0644
  install_file "$REPO_ROOT/packages/systemd/raspike-network-auth.service" "$SYSTEMD_DIR/raspike-network-auth.service" 0644
  install_file "$REPO_ROOT/packages/systemd/raspike-update.service" "$SYSTEMD_DIR/raspike-update.service" 0644
}

install_udev() {
  local serial_rule="$UDEV_RULES_DIR/99-serial.rules"
  local serial_backup="$RASPIKE_ROOT/backups/udev/99-serial.rules.original"

  log "udev rule を配置します"

  if [[ -f "$serial_rule" ]] && ! grep -q "$RASPIKE_MANAGED_MARKER" "$serial_rule"; then
    if [[ ! -f "$serial_backup" ]]; then
      log "既存の libspike 由来 udev rule をバックアップします: $serial_backup"
      install_file "$serial_rule" "$serial_backup" 0644 root root
    else
      log "udev rule のバックアップは既に存在します: $serial_backup"
    fi
  fi

  # libraspike-art のセットアップが /dev/USB_SPIKE を実機に割り当てる
  # /etc/udev/rules.d/99-serial.rules を作るため、platform 管理版で置き換えます。
  # /dev/USB_SPIKE は bridge が作る PTY に使うので、実機は /dev/raspike-real に固定します。
  install_file "$REPO_ROOT/packages/udev/99-serial.rules" "$serial_rule" 0644
}

install_network_dispatcher() {
  log "NetworkManager dispatcher を配置します"
  install_file "$REPO_ROOT/packages/network/dispatcher.sh" "$NM_DISPATCHER_DIR/90-raspike-school-auth" 0755
  install_file "$REPO_ROOT/packages/network/school-auth.sh" "$RASPIKE_ROOT/scripts/school-auth.sh" 0755 "$RASPIKE_USER" "$RASPIKE_GROUP"
}

install_update_script() {
  install_file "$REPO_ROOT/installer/update.sh" "$RASPIKE_ROOT/scripts/update.sh" 0755 "$RASPIKE_USER" "$RASPIKE_GROUP"
}

main() {
  require_root
  require_command install
  require_command mktemp

  ensure_user
  ensure_dirs
  install_bridge
  install_web
  install_configs
  install_systemd
  install_udev
  install_network_dispatcher
  install_update_script

  log "systemd と udev を再読み込みします"
  systemctl_if_available daemon-reload
  udevadm control --reload-rules || warn "udev rule の reload に失敗しました"

  log "bridge/web service を enable します"
  systemctl_if_available enable raspike-bridge.service
  systemctl_if_available enable raspike-web.service

  log "network-auth/update service は enable しません。必要時に手動または dispatcher から起動します"
  log "完了しました。起動するには: sudo systemctl start raspike-bridge.service raspike-web.service"
}

main "$@"
