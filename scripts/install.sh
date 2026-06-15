#!/usr/bin/env bash
set -euo pipefail

# Bootstrap installer for one-line installation:
#
#   curl -fsSL https://raw.githubusercontent.com/Elic0de/raspike-platform/main/scripts/install.sh | sudo bash
#
# This script downloads the full repository archive because installer/install.sh
# needs packages/systemd, packages/udev, packages/network, and packages/config.

RASPIKE_PLATFORM_REPO="${RASPIKE_PLATFORM_REPO:-Elic0de/raspike-platform}"
RASPIKE_PLATFORM_REF="${RASPIKE_PLATFORM_REF:-main}"
RASPIKE_PLATFORM_ARCHIVE_URL="${RASPIKE_PLATFORM_ARCHIVE_URL:-https://codeload.github.com/${RASPIKE_PLATFORM_REPO}/tar.gz/${RASPIKE_PLATFORM_REF}}"

log() {
  printf '[raspike-platform-bootstrap] %s\n' "$*"
}

die() {
  printf '[raspike-platform-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "必要なコマンドがありません: $1"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "root 権限で実行してください: curl ... | sudo bash"
fi

require_command curl
require_command tar
require_command mktemp

if [[ -z "${RASPIKE_PLATFORM_COMMIT:-}" ]]; then
  RASPIKE_PLATFORM_COMMIT="$(
    curl --fail --silent --location --retry 3 --retry-delay 2 \
      "https://api.github.com/repos/${RASPIKE_PLATFORM_REPO}/commits/${RASPIKE_PLATFORM_REF}" \
      | sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",[[:space:]]*$/\1/p' \
      | head -n 1
  )" || true
  export RASPIKE_PLATFORM_COMMIT
fi
if [[ -z "${RASPIKE_PLATFORM_DESCRIBE:-}" && -n "${RASPIKE_PLATFORM_COMMIT:-}" ]]; then
  RASPIKE_PLATFORM_DESCRIBE="${RASPIKE_PLATFORM_COMMIT:0:7}"
  export RASPIKE_PLATFORM_DESCRIBE
fi
export RASPIKE_PLATFORM_REPO
export RASPIKE_PLATFORM_REF
export RASPIKE_PLATFORM_ARCHIVE_URL

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

archive="$tmpdir/raspike-platform.tar.gz"
extract_dir="$tmpdir/src"
mkdir -p "$extract_dir"

log "repository archive を取得します: $RASPIKE_PLATFORM_ARCHIVE_URL"
curl --fail --location --retry 3 --retry-delay 2 --output "$archive" "$RASPIKE_PLATFORM_ARCHIVE_URL"

log "repository archive を展開します"
tar -xzf "$archive" -C "$extract_dir" --strip-components=1

if [[ ! -x "$extract_dir/installer/install.sh" ]]; then
  die "installer/install.sh が見つからないか実行できません"
fi

log "installer/install.sh を実行します"
exec "$extract_dir/installer/install.sh" "$@"
