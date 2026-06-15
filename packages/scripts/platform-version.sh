#!/usr/bin/env bash
set -euo pipefail

RASPIKE_ROOT="${RASPIKE_ROOT:-/opt/raspike}"
VERSION_FILE="${RASPIKE_PLATFORM_VERSION_FILE:-$RASPIKE_ROOT/config/platform-version.env}"

if [[ ! -r "$VERSION_FILE" ]]; then
  printf 'raspike-platform version metadata not found: %s\n' "$VERSION_FILE" >&2
  printf 'Please run the raspike-platform installer first.\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$VERSION_FILE"

printf 'raspike-platform\n'
printf '  installed_at: %s\n' "${RASPIKE_PLATFORM_INSTALLED_AT:-unknown}"
printf '  repo:         %s\n' "${RASPIKE_PLATFORM_REPO:-unknown}"
printf '  ref:          %s\n' "${RASPIKE_PLATFORM_REF:-unknown}"
printf '  commit:       %s\n' "${RASPIKE_PLATFORM_COMMIT:-unknown}"
printf '  version:      %s\n' "${RASPIKE_PLATFORM_DESCRIBE:-unknown}"

if [[ -n "${RASPIKE_PLATFORM_ARCHIVE_URL:-}" ]]; then
  printf '  archive_url:  %s\n' "$RASPIKE_PLATFORM_ARCHIVE_URL"
fi
