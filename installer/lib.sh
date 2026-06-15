#!/usr/bin/env bash
set -euo pipefail

# Shared installer helpers. Keep this file small so install/update/uninstall
# remain easy to read and each script's responsibility stays visible.

RASPIKE_ROOT="${RASPIKE_ROOT:-/opt/raspike}"
RASPIKE_USER="${RASPIKE_USER:-raspike}"
RASPIKE_GROUP="${RASPIKE_GROUP:-$RASPIKE_USER}"
RASPIKE_MANAGED_MARKER="raspike-platform managed file"
RASPIKE_PLATFORM_VERSION_FILE="${RASPIKE_PLATFORM_VERSION_FILE:-$RASPIKE_ROOT/config/platform-version.env}"

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

run_as_raspike() {
  if [[ "$(id -u)" -eq "$(id -u "$RASPIKE_USER")" ]]; then
    "$@"
    return
  fi

  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$RASPIKE_USER" -- "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -u "$RASPIKE_USER" -- "$@"
    return
  fi

  die "runuser または sudo が見つからないため '$RASPIKE_USER' として実行できません"
}

ensure_user() {
  if id "$RASPIKE_USER" >/dev/null 2>&1; then
    log "ユーザー '$RASPIKE_USER' は既に存在します"
  else
    log "ユーザー '$RASPIKE_USER' を作成します"
    useradd --system --create-home --shell /bin/bash "$RASPIKE_USER"
  fi

  local groups=()
  getent group dialout >/dev/null 2>&1 && groups+=(dialout)
  getent group input >/dev/null 2>&1 && groups+=(input)

  if [[ ${#groups[@]} -gt 0 ]]; then
    log "ユーザー '$RASPIKE_USER' を補助グループに追加します: ${groups[*]}"
    usermod -aG "$(IFS=,; printf '%s' "${groups[*]}")" "$RASPIKE_USER"
  fi
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

platform_git_value() {
  local key="$1"

  if [[ ! -d "$REPO_ROOT/.git" ]] || ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  case "$key" in
    commit)
      git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null
      ;;
    describe)
      git -C "$REPO_ROOT" describe --tags --always --dirty 2>/dev/null
      ;;
    ref)
      git -C "$REPO_ROOT" branch --show-current 2>/dev/null \
        || git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null
      ;;
    repo)
      git -C "$REPO_ROOT" remote get-url origin 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

write_platform_version() {
  local installed_at source_repo source_ref source_archive commit describe

  installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  source_repo="${RASPIKE_PLATFORM_REPO:-$(platform_git_value repo || true)}"
  source_ref="${RASPIKE_PLATFORM_REF:-$(platform_git_value ref || true)}"
  source_archive="${RASPIKE_PLATFORM_ARCHIVE_URL:-}"
  commit="${RASPIKE_PLATFORM_COMMIT:-$(platform_git_value commit || true)}"
  describe="${RASPIKE_PLATFORM_DESCRIBE:-$(platform_git_value describe || true)}"
  if [[ -z "$describe" && -n "$commit" ]]; then
    describe="${commit:0:7}"
  fi

  install -d -m 0755 -o "$RASPIKE_USER" -g "$RASPIKE_GROUP" "$(dirname "$RASPIKE_PLATFORM_VERSION_FILE")"
  {
    printf 'RASPIKE_PLATFORM_INSTALLED_AT=%q\n' "$installed_at"
    printf 'RASPIKE_PLATFORM_REPO=%q\n' "$source_repo"
    printf 'RASPIKE_PLATFORM_REF=%q\n' "$source_ref"
    printf 'RASPIKE_PLATFORM_ARCHIVE_URL=%q\n' "$source_archive"
    printf 'RASPIKE_PLATFORM_COMMIT=%q\n' "$commit"
    printf 'RASPIKE_PLATFORM_DESCRIBE=%q\n' "$describe"
  } > "$RASPIKE_PLATFORM_VERSION_FILE"
  chown "$RASPIKE_USER:$RASPIKE_GROUP" "$RASPIKE_PLATFORM_VERSION_FILE"
  chmod 0644 "$RASPIKE_PLATFORM_VERSION_FILE"
}
