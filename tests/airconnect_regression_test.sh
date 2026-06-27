#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_SCRIPT="$ROOT_DIR/scripts/airconnect-service.sh"
FORMULA_FILE="$ROOT_DIR/Formula/airconnect.rb"
MANAGER_SCRIPT="$ROOT_DIR/scripts/airconnect-manager.sh"
UPDATER_SCRIPT="$ROOT_DIR/scripts/update-airconnect-release.rb"

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

test_workflow_uses_updater_and_verifies_diff() {
  local output
  output="$(
    ruby -e '
      workflow = File.read(ARGV[0])
      uses_updater = workflow.include?("ruby scripts/update-airconnect-release.rb")
      runs_tests = workflow.include?("bash tests/airconnect_regression_test.sh")
      verifies_expected_paths = workflow.include?("unexpected = changed - expected")
      has_add_paths = workflow.include?("add-paths: |") && workflow.include?("Formula/airconnect.rb")
      uses_safe_release_notes = workflow.include?("steps.update.outputs.release_notes_block")
      packages_support_archive = workflow.include?("homebrew-airconnect-support-${VERSION}.tar.gz") &&
        workflow.include?("gh release upload") &&
        workflow.include?("resource \"airconnect-support\"")
      no_manual_commit = !workflow.include?("git commit")
      puts(uses_updater && runs_tests && verifies_expected_paths && has_add_paths && uses_safe_release_notes && packages_support_archive && no_manual_commit ? "ok" : "missing")
    ' "$ROOT_DIR/.github/workflows/update-airconnect.yml"
  )"

  [[ "$output" == "ok" ]] || fail "workflow should delegate updates, enforce diff scope, restrict PR paths, and use safe release notes"
}

test_airconnect_updater_updates_formula_and_is_idempotent() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/Formula" "$tmpdir/scripts"

  cat >"$tmpdir/Formula/airconnect.rb" <<'EOF'
class Airconnect < Formula
  url "https://github.com/philippe44/AirConnect/releases/download/1.8.3/AirConnect-1.8.3.zip"
  sha256 "oldsha"
end
EOF

  cat >"$tmpdir/scripts/airconnect-manager.sh" <<'EOF'
AIRCONNECT_VERSION="1.8.3"
EOF

  cat >"$tmpdir/CHANGELOG.md" <<'EOF'
# Changelog

## [1.8.3] - 2024-03-15

### Updated
- AirConnect from version  to 1.8.3
EOF

  AIRCONNECT_UPDATER_OFFLINE=1 \
    AIRCONNECT_UPDATER_ROOT="$tmpdir" \
    FORMULA_FILE="Formula/airconnect.rb" \
    AIRCONNECT_UPDATER_VERSION="1.9.3" \
    AIRCONNECT_UPDATER_SHA256="9ad2bf7397e1c7617c3112dd4c450b5f403a62470ad9e9e6a04db1b0f2f6db73" \
    AIRCONNECT_UPDATER_RELEASE_DATE="2025-11-21" \
    AIRCONNECT_UPDATER_FILE_SIZE="90.2" \
    ruby "$UPDATER_SCRIPT" >/dev/null

  local formula
  formula="$(cat "$tmpdir/Formula/airconnect.rb")"
  assert_contains "$formula" 'releases/download/1.9.3/AirConnect-1.9.3.zip' "updater should change Formula URL to the new version"
  assert_contains "$formula" 'sha256 "9ad2bf7397e1c7617c3112dd4c450b5f403a62470ad9e9e6a04db1b0f2f6db73"' "updater should change Formula sha256"

  local manager
  manager="$(cat "$tmpdir/scripts/airconnect-manager.sh")"
  assert_contains "$manager" 'AIRCONNECT_VERSION="1.9.3"' "updater should change manager AirConnect version"

  AIRCONNECT_UPDATER_OFFLINE=1 \
    AIRCONNECT_UPDATER_ROOT="$tmpdir" \
    FORMULA_FILE="Formula/airconnect.rb" \
    AIRCONNECT_UPDATER_VERSION="1.9.3" \
    AIRCONNECT_UPDATER_SHA256="9ad2bf7397e1c7617c3112dd4c450b5f403a62470ad9e9e6a04db1b0f2f6db73" \
    AIRCONNECT_UPDATER_RELEASE_DATE="2025-11-21" \
    AIRCONNECT_UPDATER_FILE_SIZE="90.2" \
    ruby "$UPDATER_SCRIPT" >/dev/null

  local entry_count
  entry_count="$(grep -c '^## \[1\.9\.3\]' "$tmpdir/CHANGELOG.md")"
  [[ "$entry_count" == "1" ]] || fail "updater should not duplicate changelog entries for the same version"

  rm -rf "$tmpdir"
}

test_airconnect_updater_ignores_release_note_headings_when_checking_changelog_entries() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/Formula" "$tmpdir/scripts"

  cat >"$tmpdir/Formula/airconnect.rb" <<'EOF'
class Airconnect < Formula
  url "https://github.com/philippe44/AirConnect/releases/download/1.8.3/AirConnect-1.8.3.zip"
  sha256 "oldsha"
end
EOF

  cat >"$tmpdir/scripts/airconnect-manager.sh" <<'EOF'
AIRCONNECT_VERSION="1.8.3"
EOF

  cat >"$tmpdir/CHANGELOG.md" <<'EOF'
# Changelog
EOF

  AIRCONNECT_UPDATER_OFFLINE=1 \
    AIRCONNECT_UPDATER_ROOT="$tmpdir" \
    FORMULA_FILE="Formula/airconnect.rb" \
    AIRCONNECT_UPDATER_VERSION="1.9.3" \
    AIRCONNECT_UPDATER_SHA256="9ad2bf7397e1c7617c3112dd4c450b5f403a62470ad9e9e6a04db1b0f2f6db73" \
    AIRCONNECT_UPDATER_RELEASE_DATE="2025-11-21" \
    AIRCONNECT_UPDATER_FILE_SIZE="90.2" \
    AIRCONNECT_UPDATER_RELEASE_NOTES=$'## [1.9.3]\n- upstream note with matching heading\n| column | value |' \
    ruby "$UPDATER_SCRIPT" >/dev/null

  local changelog
  changelog="$(cat "$tmpdir/CHANGELOG.md")"
  assert_contains "$changelog" '<!-- airconnect-updater:version=1.9.3 -->' "updater should add a machine-readable changelog marker"

  local marker_count
  marker_count="$(grep -c '<!-- airconnect-updater:version=1\.9\.3 -->' "$tmpdir/CHANGELOG.md")"
  [[ "$marker_count" == "1" ]] || fail "updater should count changelog entries by marker, not release-note headings"

  rm -rf "$tmpdir"
}

test_formula_uses_pinned_support_resources() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      uses_tap_checkout = formula.include?("Pathname(__dir__).parent") ||
        formula.include?("support_root") ||
        formula.include?("Library/Taps")
      has_support_archive = formula.include?("resource \"airconnect-support\"") &&
        formula.match?(%r{github.com/dmego/homebrew-airconnect/releases/download/airconnect-support-[^/]+/homebrew-airconnect-support-[^/]+\.tar\.gz})
      has_split_raw_resources = formula.include?("raw.githubusercontent.com") ||
        formula.include?("resource \"airconnect-service\"") ||
        formula.include?("resource \"airconnect-manager\"") ||
        formula.include?("resource \"airconnect-config\"")
      puts(!uses_tap_checkout && has_support_archive && !has_split_raw_resources ? "resource" : "tap-checkout")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "resource" ]] || fail "Formula should install support files from pinned resources instead of the tap checkout"
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

test_formula_ignores_missing_quarantine_xattr() {
  local output
  output="$(
    ruby -e '
      formula = File.read(ARGV[0])
      fatal_xattr_delete = formula.match?(/^\s*system "xattr", "-d", "com\.apple\.quarantine"/)
      nonfatal_xattr_delete = formula.match?(/^\s*quiet_system "xattr", "-d", "com\.apple\.quarantine"/)
      puts(!fatal_xattr_delete && nonfatal_xattr_delete ? "nonfatal" : "fatal")
    ' "$FORMULA_FILE"
  )"

  [[ "$output" == "nonfatal" ]] || fail "Formula should not fail when quarantine xattr is absent"
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
test_workflow_uses_updater_and_verifies_diff
test_airconnect_updater_updates_formula_and_is_idempotent
test_airconnect_updater_ignores_release_note_headings_when_checking_changelog_entries
test_formula_uses_pinned_support_resources
test_formula_uninstall_preserves_user_config
test_formula_avoids_shell_rm_rf
test_formula_requires_fileutils
test_formula_ignores_missing_quarantine_xattr
test_manager_reset_noninteractive
test_service_log_rotation

echo "All regression checks passed"
