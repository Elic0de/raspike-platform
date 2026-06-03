#!/usr/bin/env bash
set -euo pipefail

WEB_DIR="${RASPIKE_WEB_DIR:-/opt/raspike/apps/web}"
NODE_BIN="${RASPIKE_NODE_BIN:-}"

find_node() {
  if [[ -n "$NODE_BIN" ]]; then
    [[ -x "$NODE_BIN" ]] || {
      printf '[raspike-web] RASPIKE_NODE_BIN is not executable: %s\n' "$NODE_BIN" >&2
      return 1
    }
    printf '%s\n' "$NODE_BIN"
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi

  if command -v nodejs >/dev/null 2>&1; then
    command -v nodejs
    return 0
  fi

  local candidate
  for candidate in \
    /usr/local/bin/node \
    /usr/bin/node \
    /usr/bin/nodejs \
    /opt/node/bin/node \
    /home/raspike/.nvm/versions/node/*/bin/node; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if [[ ! -f "$WEB_DIR/server.mjs" ]]; then
  printf '[raspike-web] server.mjs not found: %s/server.mjs\n' "$WEB_DIR" >&2
  exit 1
fi

resolved_node="$(find_node)" || {
  printf '[raspike-web] node runtime not found. Install nodejs or set RASPIKE_NODE_BIN in /opt/raspike/config/raspike.env\n' >&2
  exit 127
}

cd "$WEB_DIR"
exec "$resolved_node" server.mjs
