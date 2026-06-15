#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer/lib.sh
source "$SCRIPT_DIR/lib.sh"

BRIDGE_REPO_URL="${BRIDGE_REPO_URL:-https://github.com/Elic0de/raspike-bridge-ps5.git}"
BRIDGE_REF="${BRIDGE_REF:-main}"
WEB_RELEASE_REPO="${WEB_RELEASE_REPO:-Elic0de/raspike-web-control-v3}"
WEB_RELEASE_ASSET="${WEB_RELEASE_ASSET:-dist.zip}"
WEB_DIST_URL="${WEB_DIST_URL:-$(github_latest_asset_url "$WEB_RELEASE_REPO" "$WEB_RELEASE_ASSET")}"
INSTALL_WEB_TMPDIR=""

cleanup_install() {
  if [[ -n "${INSTALL_WEB_TMPDIR:-}" ]]; then
    rm -rf "$INSTALL_WEB_TMPDIR"
  fi
}
trap cleanup_install EXIT

validate_web_bundle() {
  local web_dir="$1"

  [[ -f "$web_dir/server.mjs" ]] || die "web bundle に server.mjs がありません: $web_dir"
  [[ -f "$web_dir/dist/index.html" ]] || die "web bundle に dist/index.html がありません: $web_dir"
}

ensure_node_runtime() {
  if command -v node >/dev/null 2>&1 || command -v nodejs >/dev/null 2>&1; then
    log "Node.js runtime は既に利用できます"
    return
  fi

  if [[ "${RASPIKE_SKIP_NODE_INSTALL:-false}" == "true" ]]; then
    warn "Node.js runtime が見つかりません。raspike-web.service 起動前に node または nodejs を用意してください"
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "Node.js runtime が見つからないため apt-get で nodejs をインストールします"
    apt-get update
    apt-get install -y nodejs
    return
  fi

  warn "Node.js runtime が見つからず、自動インストールもできません。raspike-web.service 起動前に node または nodejs を用意してください"
}

install_bridge() {
  require_command git

  if [[ -d "$RASPIKE_ROOT/apps/bridge/.git" ]]; then
    log "bridge repo は既に clone 済みです。fetch して $BRIDGE_REF に合わせます"
    chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_ROOT/apps/bridge"
    run_as_raspike git -C "$RASPIKE_ROOT/apps/bridge" fetch --all --tags --prune
    run_as_raspike git -C "$RASPIKE_ROOT/apps/bridge" checkout "$BRIDGE_REF"
    run_as_raspike git -C "$RASPIKE_ROOT/apps/bridge" pull --ff-only || warn "bridge の pull に失敗しました。ローカル状態を確認してください"
  else
    log "bridge repo を clone します: $BRIDGE_REPO_URL"
    rm -rf "$RASPIKE_ROOT/apps/bridge"
    run_as_raspike git clone --branch "$BRIDGE_REF" "$BRIDGE_REPO_URL" "$RASPIKE_ROOT/apps/bridge"
  fi

  chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_ROOT/apps/bridge"
}

install_web() {
  require_command unzip
  INSTALL_WEB_TMPDIR="$(mktemp -d)"
  local tmpdir="$INSTALL_WEB_TMPDIR"

  download_file "$WEB_DIST_URL" "$tmpdir/dist.zip"

  log "web dist.zip を展開します"
  rm -rf "$tmpdir/web"
  mkdir -p "$tmpdir/web"
  unzip -q "$tmpdir/dist.zip" -d "$tmpdir/web"
  validate_web_bundle "$tmpdir/web"

  backup_path "$RASPIKE_ROOT/apps/web"
  mkdir -p "$RASPIKE_ROOT/apps"
  mv "$tmpdir/web" "$RASPIKE_ROOT/apps/web"
  chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_ROOT/apps/web"
  rm -rf "$tmpdir"
  INSTALL_WEB_TMPDIR=""
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

install_platform_version_script() {
  install_file "$REPO_ROOT/packages/scripts/platform-version.sh" "$RASPIKE_ROOT/scripts/platform-version.sh" 0755 "$RASPIKE_USER" "$RASPIKE_GROUP"
  install_file "$REPO_ROOT/packages/scripts/platform-version.sh" "/usr/local/bin/raspike-platform-version" 0755 root root
}

install_web_runner() {
  install_file "$REPO_ROOT/packages/scripts/run-web.sh" "$RASPIKE_ROOT/scripts/run-web.sh" 0755 "$RASPIKE_USER" "$RASPIKE_GROUP"
}

main() {
  require_root
  require_command install
  require_command mktemp

  ensure_user
  ensure_dirs
  ensure_node_runtime
  install_bridge
  install_web
  install_configs
  install_systemd
  install_udev
  install_network_dispatcher
  install_update_script
  install_platform_version_script
  install_web_runner
  write_platform_version

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
