#!/usr/bin/env bash
set -euo pipefail

# School Wi-Fi captive portal authentication.
# Secrets are loaded from /opt/raspike/config/wifi-auth.env. Do not hard-code
# account names or passwords in this script.

RASPIKE_ROOT="${RASPIKE_ROOT:-/opt/raspike}"
AUTH_ENV="${AUTH_ENV:-$RASPIKE_ROOT/config/wifi-auth.env}"
LOG_FILE="${RASPIKE_NETWORK_AUTH_LOG:-$RASPIKE_ROOT/logs/network-auth.log}"

log() {
  local message="[raspike-network-auth] $*"
  printf '%s\n' "$message"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$message" >> "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

if [[ ! -r "$AUTH_ENV" ]]; then
  die "認証設定が読めません: $AUTH_ENV"
fi

# shellcheck source=/dev/null
source "$AUTH_ENV"

SCHOOL_AUTH_URL="${SCHOOL_AUTH_URL:-}"
SCHOOL_AUTH_METHOD="${SCHOOL_AUTH_METHOD:-POST}"
SCHOOL_AUTH_USERNAME="${SCHOOL_AUTH_USERNAME:-}"
SCHOOL_AUTH_PASSWORD="${SCHOOL_AUTH_PASSWORD:-}"
SCHOOL_AUTH_USERNAME_FIELD="${SCHOOL_AUTH_USERNAME_FIELD:-username}"
SCHOOL_AUTH_PASSWORD_FIELD="${SCHOOL_AUTH_PASSWORD_FIELD:-password}"
SCHOOL_AUTH_EXTRA_FORM="${SCHOOL_AUTH_EXTRA_FORM:-}"
SCHOOL_AUTH_SUCCESS_PATTERN="${SCHOOL_AUTH_SUCCESS_PATTERN:-}"
SCHOOL_AUTH_TIMEOUT_SEC="${SCHOOL_AUTH_TIMEOUT_SEC:-15}"

[[ -n "$SCHOOL_AUTH_URL" ]] || die "SCHOOL_AUTH_URL が未設定です"
[[ -n "$SCHOOL_AUTH_USERNAME" ]] || die "SCHOOL_AUTH_USERNAME が未設定です"
[[ -n "$SCHOOL_AUTH_PASSWORD" ]] || die "SCHOOL_AUTH_PASSWORD が未設定です"
command -v curl >/dev/null 2>&1 || die "curl が見つかりません"

tmp_response="$(mktemp)"
trap 'rm -f "$tmp_response"' EXIT

log "学校 Wi-Fi 認証を開始します: $SCHOOL_AUTH_URL"

curl_args=(
  --fail
  --location
  --silent
  --show-error
  --max-time "$SCHOOL_AUTH_TIMEOUT_SEC"
  --output "$tmp_response"
)

if [[ "$SCHOOL_AUTH_METHOD" == "POST" ]]; then
  curl_args+=(
    --request POST
    --data-urlencode "$SCHOOL_AUTH_USERNAME_FIELD=$SCHOOL_AUTH_USERNAME"
    --data-urlencode "$SCHOOL_AUTH_PASSWORD_FIELD=$SCHOOL_AUTH_PASSWORD"
  )

  if [[ -n "$SCHOOL_AUTH_EXTRA_FORM" ]]; then
    # SCHOOL_AUTH_EXTRA_FORM は "key=value&key2=value2" 形式を想定します。
    IFS='&' read -r -a extra_pairs <<< "$SCHOOL_AUTH_EXTRA_FORM"
    for pair in "${extra_pairs[@]}"; do
      [[ -n "$pair" ]] && curl_args+=(--data-urlencode "$pair")
    done
  fi
else
  curl_args+=(--request "$SCHOOL_AUTH_METHOD")
fi

if ! curl "${curl_args[@]}" "$SCHOOL_AUTH_URL"; then
  die "認証リクエストに失敗しました"
fi

if [[ -n "$SCHOOL_AUTH_SUCCESS_PATTERN" ]]; then
  if grep -q "$SCHOOL_AUTH_SUCCESS_PATTERN" "$tmp_response"; then
    log "認証成功を確認しました"
  else
    die "成功パターンがレスポンスに見つかりません"
  fi
else
  log "認証リクエストが成功しました"
fi

if [[ "${RASPIKE_RUN_UPDATE_AFTER_AUTH:-false}" == "true" ]]; then
  log "認証成功後の update を起動します"
  systemctl start raspike-update.service || log "update service の起動に失敗しました"
fi
