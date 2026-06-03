#!/usr/bin/env bash
set -euo pipefail

# Shared installer helpers. Keep this file small so install/update/uninstall
# remain easy to read and each script's responsibility stays visible.

RASPIKE_ROOT="${RASPIKE_ROOT:-/opt/raspike}"
RASPIKE_USER="${RASPIKE_USER:-raspike}"
RASPIKE_GROUP="${RASPIKE_GROUP:-$RASPIKE_USER}"
RASPIKE_MANAGED_MARKER="raspike-platform managed file"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
UDEV_RULES_DIR="${UDEV_RULES_DIR:-/etc/udev/rules.d}"
NM_DISPATCHER_DIR="${NM_DISPATCHER_DIR:-/etc/NetworkManager/dispatcher.d}"

log() {
  printf '[raspike-platform] %s\n' "$*"
}

warn() {
  printf '[raspike-platform] WARN: %s\n' "$*" >&2
}

die() {
  printf '[raspike-platform] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "root 権限で実行してください: sudo $0"
  fi
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "必要なコマンドがありません: $cmd"
}

ensure_user() {
  if id "$RASPIKE_USER" >/dev/null 2>&1; then
    log "ユーザー '$RASPIKE_USER' は既に存在します"
    return
  fi

  log "ユーザー '$RASPIKE_USER' を作成します"
  useradd --system --create-home --shell /bin/bash "$RASPIKE_USER"
}

ensure_dirs() {
  log "$RASPIKE_ROOT のディレクトリを作成します"
  install -d -m 0755 "$RASPIKE_ROOT"
  install -d -m 0755 "$RASPIKE_ROOT/apps/bridge"
  install -d -m 0755 "$RASPIKE_ROOT/apps/web"
  install -d -m 0755 "$RASPIKE_ROOT/backups/udev"
  install -d -m 0755 "$RASPIKE_ROOT/config"
  install -d -m 0755 "$RASPIKE_ROOT/scripts"
  install -d -m 0755 "$RASPIKE_ROOT/logs"
  chown -R "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_ROOT"
}

backup_path() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  local stamp
  stamp="$(date +%Y%m%d%H%M%S)"
  local backup="${path}.bak.${stamp}"
  log "既存ファイルをバックアップします: $path -> $backup"
  mv "$path" "$backup"
}

install_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"
  local owner="${4:-root}"
  local group="${5:-root}"

  install -D -m "$mode" -o "$owner" -g "$group" "$src" "$dst"
}

copy_config_if_missing() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [[ -f "$dst" ]]; then
    log "設定ファイルは既存のものを維持します: $dst"
    return
  fi

  install_file "$src" "$dst" "$mode" "$RASPIKE_USER" "$RASPIKE_GROUP"
}

github_latest_asset_url() {
  local repo="$1"
  local asset="$2"
  printf 'https://github.com/%s/releases/latest/download/%s' "$repo" "$asset"
}

download_file() {
  local url="$1"
  local dst="$2"

  require_command curl
  log "ダウンロードします: $url"
  curl --fail --location --retry 3 --retry-delay 2 --output "$dst" "$url"
}

systemctl_if_available() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl "$@"
  else
    warn "systemctl が見つからないためスキップします: systemctl $*"
  fi
}
