#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib.sh" ]]; then
  # Running from the repository.
  # shellcheck source=installer/lib.sh
  source "$SCRIPT_DIR/lib.sh"
else
  # Running from /opt/raspike/scripts after installation.
  RASPIKE_ROOT="${RASPIKE_ROOT:-/opt/raspike}"
  RASPIKE_USER="${RASPIKE_USER:-raspike}"
  RASPIKE_GROUP="${RASPIKE_GROUP:-$RASPIKE_USER}"
  log() { printf '[raspike-update] %s\n' "$*"; }
  warn() { printf '[raspike-update] WARN: %s\n' "$*" >&2; }
  die() { printf '[raspike-update] ERROR: %s\n' "$*" >&2; exit 1; }
  require_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "root 権限で実行してください"; }
  require_command() { command -v "$1" >/dev/null 2>&1 || die "必要なコマンドがありません: $1"; }
  github_latest_asset_url() { printf 'https://github.com/%s/releases/latest/download/%s' "$1" "$2"; }
  download_file() { require_command curl; curl --fail --location --retry 3 --retry-delay 2 --output "$2" "$1"; }
  systemctl_if_available() { command -v systemctl >/dev/null 2>&1 && systemctl "$@" || true; }

  if [[ -r "$RASPIKE_ROOT/config/raspike.env" ]]; then
    # shellcheck source=/dev/null
    source "$RASPIKE_ROOT/config/raspike.env"
  fi
fi

BRIDGE_REF="${BRIDGE_REF:-main}"
WEB_RELEASE_REPO="${WEB_RELEASE_REPO:-Elic0de/raspike-web-control-v3}"
WEB_RELEASE_ASSET="${WEB_RELEASE_ASSET:-dist.zip}"
WEB_DIST_URL="${WEB_DIST_URL:-$(github_latest_asset_url "$WEB_RELEASE_REPO" "$WEB_RELEASE_ASSET")}"

validate_web_bundle() {
  local web_dir="$1"

  [[ -f "$web_dir/server.mjs" ]] || die "web bundle に server.mjs がありません: $web_dir"
  [[ -f "$web_dir/dist/index.html" ]] || die "web bundle に dist/index.html がありません: $web_dir"
}

update_bridge() {
  require_command git
  local bridge_dir="$RASPIKE_ROOT/apps/bridge"

  if [[ ! -d "$bridge_dir/.git" ]]; then
    warn "bridge repo が見つからないためスキップします: $bridge_dir"
    return
  fi

  log "bridge を更新します: ref=$BRIDGE_REF"
  git -C "$bridge_dir" fetch --all --tags --prune
  git -C "$bridge_dir" checkout "$BRIDGE_REF"
  git -C "$bridge_dir" pull --ff-only
  chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$bridge_dir"
}

update_web() {
  require_command unzip
  local web_dir="$RASPIKE_ROOT/apps/web"
  local backup_dir="$RASPIKE_ROOT/apps/web.backup.$(date +%Y%m%d%H%M%S)"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  download_file "$WEB_DIST_URL" "$tmpdir/dist.zip"
  mkdir -p "$tmpdir/web"
  unzip -q "$tmpdir/dist.zip" -d "$tmpdir/web"
  validate_web_bundle "$tmpdir/web"

  log "web をバックアップして差し替えます"
  if [[ -d "$web_dir" ]]; then
    mv "$web_dir" "$backup_dir"
  fi

  if mv "$tmpdir/web" "$web_dir"; then
    chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$web_dir"
    log "web 更新完了。バックアップ: $backup_dir"
  else
    warn "web 差し替えに失敗しました。rollback します"
    rm -rf "$web_dir"
    if [[ -d "$backup_dir" ]]; then
      mv "$backup_dir" "$web_dir"
    fi
    die "web 更新に失敗しました"
  fi
}

restart_services() {
  log "必要な service だけ restart します"
  systemctl_if_available restart raspike-bridge.service
  systemctl_if_available restart raspike-web.service
}

main() {
  require_root
  require_command mktemp

  update_bridge
  update_web
  restart_services
  log "更新が完了しました"
}

main "$@"
