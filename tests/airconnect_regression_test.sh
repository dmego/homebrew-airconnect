#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_SCRIPT="$ROOT_DIR/scripts/airconnect-service.sh"
FORMULA_FILE="$ROOT_DIR/Formula/airconnect.rb"
MANAGER_SCRIPT="$ROOT_DIR/scripts/airconnect-manager.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

test_service_argument_translation() {
  local prefix
  prefix="$(mktemp -d)"
  mkdir -p "$prefix/bin" "$prefix/etc/airconnect" "$prefix/var/log" "$prefix/var/run"

  cat >"$prefix/etc/airconnect/airconnect.conf" <<'EOF'
NETWORK_INTERFACE="en0"
AIRCAST_CONFIG_XML="/tmp/aircast config.xml"
AIRUPNP_NETWORK_INTERFACE="192.168.1.20"
AIRUPNP_CONFIG_XML="/tmp/airupnp.xml"
EOF

  local output
  output="$(
    HOMEBREW_PREFIX="$prefix" \
    bash -c '
      source "'"$SERVICE_SCRIPT"'"
      printf "aircast:\n"
      while IFS= read -r -d "" arg; do
        printf "<%s>\n" "$arg"
      done < <(build_service_argv aircast)
      printf "airupnp:\n"
      while IFS= read -r -d "" arg; do
        printf "<%s>\n" "$arg"
      done < <(build_service_argv airupnp)
    '
  )"

  assert_contains "$output" 'aircast:' "service test harness did not return aircast command"
  assert_contains "$output" '<-b>' "network interface flag should be added to service arguments"
  assert_contains "$output" '<en0>' "NETWORK_INTERFACE should translate to en0 for aircast"
  assert_contains "$output" '<-x>' "xml config flag should be added to service arguments"
  assert_contains "$output" '</tmp/aircast config.xml>' "AIRCAST_CONFIG_XML should translate to -x for aircast"
  assert_contains "$output" 'airupnp:' "service test harness did not return airupnp command"
  assert_contains "$output" '<192.168.1.20>' "AIRUPNP_NETWORK_INTERFACE should override shared interface"
  assert_contains "$output" '</tmp/airupnp.xml>' "AIRUPNP_CONFIG_XML should translate to -x for airupnp"

  rm -rf "$prefix"
}

test_formula_preserves_existing_config() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      guard = formula.include?("unless config_file.exist?")
      puts(guard ? "guarded" : "unguarded")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "guarded" ]] || fail "Formula post_install should preserve existing user config"
}

test_workflow_updates_url_and_sha_together() {
  local output
  output="$(
    ruby -e '
      workflow = File.read(ARGV[0])
      has_url_update = workflow.match?(%r{sed -i .s#\^  url "https://github.com/philippe44/AirConnect/releases/download/})
      has_sha_update = workflow.match?(%r{sed -i .s/sha256 "\[\^"\]\*"/sha256})
      puts(has_url_update && has_sha_update ? "ok" : "missing")
    ' "$ROOT_DIR/.github/workflows/update-airconnect.yml"
  )"

  [[ "$output" == "ok" ]] || fail "workflow should update formula url and sha256 together"
}

test_formula_uses_repo_support_files() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      uses_remote_support = formula.include?("raw.githubusercontent.com/dmego/homebrew-airconnect/main")
      uses_curl_download = formula.include?("system \"curl\"")
      puts(uses_remote_support || uses_curl_download ? "remote" : "local")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "local" ]] || fail "Formula should install support files from the tap checkout instead of downloading from main"
}

test_formula_uninstall_preserves_user_config() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      destructive_uninstall = formula.match?(/def uninstall.*cleanup_on_uninstall/m)
      puts(destructive_uninstall ? "destructive" : "preserving")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "preserving" ]] || fail "Formula uninstall should not call the full cleanup routine"
}

test_formula_avoids_shell_rm_rf() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      dangerous_shell_delete = formula.include?("system \"rm -rf") || formula.include?("system \"rm -f")
      puts(dangerous_shell_delete ? "dangerous" : "safe")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "safe" ]] || fail "Formula should use Ruby file deletion helpers instead of shell rm"
}

test_formula_requires_fileutils() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      puts(formula.start_with?("require \"fileutils\"") ? "required" : "missing")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "required" ]] || fail "Formula should require fileutils before using FileUtils helpers"
}

test_manager_reset_noninteractive() {
  local prefix
  prefix="$(mktemp -d)"
  mkdir -p "$prefix/etc/airconnect"

  if ! HOMEBREW_PREFIX="$prefix" AIRCONNECT_ASSUME_YES=1 bash "$MANAGER_SCRIPT" config reset >/dev/null 2>&1; then
    rm -rf "$prefix"
    fail "manager config reset should support non-interactive execution when AIRCONNECT_ASSUME_YES=1"
  fi

  [[ -f "$prefix/etc/airconnect/airconnect.conf" ]] || fail "manager config reset should write the config file"
  rm -rf "$prefix"
}

test_service_log_rotation() {
  local prefix
  prefix="$(mktemp -d)"
  mkdir -p "$prefix/bin" "$prefix/etc/airconnect" "$prefix/var/log" "$prefix/var/run"

  cat >"$prefix/etc/airconnect/airconnect.conf" <<'EOF'
LOG_MAX_SIZE_MB="1"
DEBUG="1"
EOF

  python3 - <<'PY' "$prefix/var/log/airconnect-service.log"
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"x" * (1024 * 1024 + 16))
PY

  HOMEBREW_PREFIX="$prefix" bash -c '
    source "'"$SERVICE_SCRIPT"'"
    log "rotation check"
  ' >/dev/null

  [[ -f "$prefix/var/log/airconnect-service.log.1" ]] || fail "service log rotation should keep one backup log"
  rm -rf "$prefix"
}

test_service_argument_translation
test_formula_preserves_existing_config
test_workflow_updates_url_and_sha_together
test_formula_uses_repo_support_files
test_formula_uninstall_preserves_user_config
test_formula_avoids_shell_rm_rf
test_formula_requires_fileutils
test_manager_reset_noninteractive
test_service_log_rotation

echo "All regression checks passed"
