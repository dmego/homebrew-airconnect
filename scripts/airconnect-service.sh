#!/bin/bash

# AirConnect Service Manager
# Manages both AirCast and AirUPnP services as a unified service
# Version: 1.0.1
# Author: dmego
# License: MIT

set -euo pipefail

# Default configuration
if [[ -z "${HOMEBREW_PREFIX:-}" ]] && command -v brew >/dev/null 2>&1; then
    HOMEBREW_PREFIX="$(brew --prefix)"
else
    HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
fi

# Source configuration if available
CONFIG_FILE="$HOMEBREW_PREFIX/etc/airconnect/airconnect.conf"
CONFIG_LOADED=0
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    CONFIG_LOADED=1
fi

AIRCAST_BIN="${AIRCAST_BIN:-$HOMEBREW_PREFIX/bin/aircast}"
AIRUPNP_BIN="${AIRUPNP_BIN:-$HOMEBREW_PREFIX/bin/airupnp}"
LOG_DIR="${LOG_DIR:-$HOMEBREW_PREFIX/var/log}"
PID_DIR="${PID_DIR:-$HOMEBREW_PREFIX/var/run}"
SERVICE_NAME="${SERVICE_NAME:-airconnect}"

# Service configuration
AIRCAST_ARGS="${AIRCAST_ARGS:--Z -d all=info}"
AIRUPNP_ARGS="${AIRUPNP_ARGS:--Z -d all=info}"
NETWORK_INTERFACE="${NETWORK_INTERFACE:-}"
AIRCAST_NETWORK_INTERFACE="${AIRCAST_NETWORK_INTERFACE:-}"
AIRUPNP_NETWORK_INTERFACE="${AIRUPNP_NETWORK_INTERFACE:-}"
AIRCAST_CONFIG_XML="${AIRCAST_CONFIG_XML:-}"
AIRUPNP_CONFIG_XML="${AIRUPNP_CONFIG_XML:-}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
RESTART_DELAY="${RESTART_DELAY:-5}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-3}"
DEBUG="${DEBUG:-0}"
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-10}"

# Log files
LOG_FILE="$LOG_DIR/airconnect-service.log"
AIRCAST_LOG="$LOG_DIR/aircast.log"
AIRUPNP_LOG="$LOG_DIR/airupnp.log"

# PID files
AIRCAST_PID="$PID_DIR/aircast.pid"
AIRUPNP_PID="$PID_DIR/airupnp.pid"
SERVICE_PID="$PID_DIR/airconnect.pid"

# Restart counters
AIRCAST_RESTART_COUNT=0
AIRUPNP_RESTART_COUNT=0
COMMAND_ARGS=()

# Ensure required directories exist
mkdir -p "$LOG_DIR" "$PID_DIR"

# Logging functions
file_size_bytes() {
    local path="$1"

    if stat -f%z "$path" >/dev/null 2>&1; then
        stat -f%z "$path"
    else
        stat -c%s "$path"
    fi
}

rotate_log_if_needed() {
    local path="$1"
    local max_size_bytes
    local current_size

    [[ "$LOG_MAX_SIZE_MB" =~ ^[0-9]+$ ]] || return 0
    [[ "$LOG_MAX_SIZE_MB" -gt 0 ]] || return 0
    [[ -f "$path" ]] || return 0

    max_size_bytes=$((LOG_MAX_SIZE_MB * 1024 * 1024))
    current_size="$(file_size_bytes "$path")"
    [[ "$current_size" -lt "$max_size_bytes" ]] && return 0

    rm -f "${path}.1"
    mv "$path" "${path}.1"
}

log() {
    rotate_log_if_needed "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SERVICE_NAME] $*" | tee -a "$LOG_FILE"
}

log_error() {
    rotate_log_if_needed "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SERVICE_NAME] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    [[ "$DEBUG" == "1" ]] || return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SERVICE_NAME] DEBUG: $*" | tee -a "$LOG_FILE"
}

run_with_timeout() {
    local seconds="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "${seconds}s" "$@"
    else
        perl -e 'alarm shift @ARGV; exec @ARGV' "$seconds" "$@"
    fi
}

service_binary_for() {
    case "$1" in
        aircast) printf '%s\n' "$AIRCAST_BIN" ;;
        airupnp) printf '%s\n' "$AIRUPNP_BIN" ;;
        *) return 1 ;;
    esac
}

service_legacy_args_for() {
    case "$1" in
        aircast) printf '%s\n' "$AIRCAST_ARGS" ;;
        airupnp) printf '%s\n' "$AIRUPNP_ARGS" ;;
        *) return 1 ;;
    esac
}

service_interface_for() {
    case "$1" in
        aircast) printf '%s\n' "${AIRCAST_NETWORK_INTERFACE:-$NETWORK_INTERFACE}" ;;
        airupnp) printf '%s\n' "${AIRUPNP_NETWORK_INTERFACE:-$NETWORK_INTERFACE}" ;;
        *) return 1 ;;
    esac
}

service_config_xml_for() {
    case "$1" in
        aircast) printf '%s\n' "$AIRCAST_CONFIG_XML" ;;
        airupnp) printf '%s\n' "$AIRUPNP_CONFIG_XML" ;;
        *) return 1 ;;
    esac
}

build_service_argv() {
    local service="$1"
    local binary
    local legacy_args
    local network_interface
    local config_xml
    local args=()
    local legacy_parts=()

    binary="$(service_binary_for "$service")"
    legacy_args="$(service_legacy_args_for "$service")"
    network_interface="$(service_interface_for "$service")"
    config_xml="$(service_config_xml_for "$service")"

    args+=("$binary")
    if [[ -n "$legacy_args" ]]; then
        # Intentionally split legacy flat args so existing AIRCAST_ARGS/AIRUPNP_ARGS
        # values keep working; structured overrides are appended separately below.
        # shellcheck disable=SC2206
        legacy_parts=($legacy_args)
        args+=("${legacy_parts[@]}")
    fi
    if [[ -n "$network_interface" ]]; then
        args+=("-b" "$network_interface")
    fi
    if [[ -n "$config_xml" ]]; then
        args+=("-x" "$config_xml")
    fi

    printf '%s\0' "${args[@]}"
}

load_service_command() {
    local service="$1"
    COMMAND_ARGS=()

    while IFS= read -r -d '' arg; do
        COMMAND_ARGS+=("$arg")
    done < <(build_service_argv "$service")
}

command_to_string() {
    local command_string=""
    local escaped_arg

    for arg in "$@"; do
        printf -v escaped_arg '%q' "$arg"
        command_string+="${command_string:+ }${escaped_arg}"
    done

    printf '%s\n' "$command_string"
}

build_service_command() {
    load_service_command "$1"
    command_to_string "${COMMAND_ARGS[@]}"
}

# Check if a process is running by PID
is_running() {
    local pid_file="$1"
    [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

# Check for Gatekeeper issues
check_gatekeeper() {
    local binary="$1"
    local binary_name=$(basename "$binary")
    
    log_debug "Starting Gatekeeper check for $binary_name"
    
    # Check if file has quarantine attribute
    log_debug "Checking quarantine attributes for $binary_name"
    if xattr -l "$binary" 2>/dev/null | grep -q "com.apple.quarantine"; then
        log_error "$binary_name is quarantined by macOS Gatekeeper"
        log_error "Run: xattr -d com.apple.quarantine $binary"
        return 1
    fi
    log_debug "No quarantine attributes found for $binary_name"
    
    # Try to execute binary with --help to test if it's blocked (with timeout)
    log_debug "Testing $binary_name execution with --help flag"
    local temp_output=$(mktemp)
    local test_pid
    
    # Run the test command in background with a portable timeout helper
    run_with_timeout 5 "$binary" --help >"$temp_output" 2>&1 &
    test_pid=$!
    
    # Wait for the command to complete or timeout
    local exit_code=0
    if wait $test_pid 2>/dev/null; then
        exit_code=0
    else
        exit_code=$?
    fi
    rm -f "$temp_output"

    if [[ $exit_code -eq 137 ]]; then
        log_error "$binary_name was killed by macOS Gatekeeper (exit code 137)"
        log_error "This usually means the binary is unsigned or blocked by security settings"
        log_error "Solutions:"
        log_error "1. Remove quarantine: xattr -d com.apple.quarantine $binary"
        log_error "2. Allow in Security & Privacy settings"
        log_error "3. Reinstall with: brew reinstall airconnect"
        return 1
    fi

    if [[ $exit_code -eq 124 || $exit_code -eq 142 ]]; then
        log_debug "$binary_name --help test timed out"
    else
        log_debug "$binary_name --help completed with exit code: $exit_code"
    fi
    
    log_debug "Gatekeeper check completed for $binary_name"
    return 0
}

# Start AirCast service
start_aircast() {
    log "Starting AirCast service..."
    log_debug "AirCast binary: $AIRCAST_BIN"
    log_debug "AirCast arguments: $AIRCAST_ARGS"
    
    if is_running "$AIRCAST_PID"; then
        log "AirCast is already running (PID: $(cat "$AIRCAST_PID"))"
        return 0
    fi
    
    # Verify binary exists
    if [[ ! -x "$AIRCAST_BIN" ]]; then
        log_error "AirCast binary not found or not executable: $AIRCAST_BIN"
        return 1
    fi
    
    # Check for Gatekeeper issues
    if ! check_gatekeeper "$AIRCAST_BIN"; then
        return 1
    fi
    
    # Start AirCast in background
    load_service_command aircast
    local command_string
    command_string="$(command_to_string "${COMMAND_ARGS[@]}")"
    log "Executing: $command_string"
    rotate_log_if_needed "$AIRCAST_LOG"
    nohup "${COMMAND_ARGS[@]}" > "$AIRCAST_LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$AIRCAST_PID"
    log "AirCast started with PID: $pid"
    
    # Verify startup with timeout
    local count=0
    local max_wait=10
    while [[ $count -lt $max_wait ]]; do
        if is_running "$AIRCAST_PID"; then
            log "AirCast started successfully (PID: $pid)"
            AIRCAST_RESTART_COUNT=0
            return 0
        fi
        sleep 1
        ((count++))
        log_debug "Waiting for AirCast to start... ($count/$max_wait)"
    done
    
    log_error "Failed to start AirCast - timeout after ${max_wait}s"
    # Check if it was killed by Gatekeeper
    if tail -1 "$AIRCAST_LOG" 2>/dev/null | grep -q "Killed"; then
        log_error "AirCast was killed, possibly by macOS Gatekeeper"
        check_gatekeeper "$AIRCAST_BIN"
    fi
    # Show last few lines of log for debugging
    log_error "Last 5 lines of AirCast log:"
    tail -5 "$AIRCAST_LOG" 2>/dev/null | while read line; do
        log_error "  $line"
    done
    rm -f "$AIRCAST_PID"
    return 1
}

# Start AirUPnP service
start_airupnp() {
    log "Starting AirUPnP service..."
    log_debug "AirUPnP binary: $AIRUPNP_BIN"
    log_debug "AirUPnP arguments: $AIRUPNP_ARGS"
    
    if is_running "$AIRUPNP_PID"; then
        log "AirUPnP is already running (PID: $(cat "$AIRUPNP_PID"))"
        return 0
    fi
    
    # Verify binary exists
    if [[ ! -x "$AIRUPNP_BIN" ]]; then
        log_error "AirUPnP binary not found or not executable: $AIRUPNP_BIN"
        return 1
    fi
    
    # Check for Gatekeeper issues
    if ! check_gatekeeper "$AIRUPNP_BIN"; then
        return 1
    fi
    
    # Start AirUPnP in background
    load_service_command airupnp
    local command_string
    command_string="$(command_to_string "${COMMAND_ARGS[@]}")"
    log "Executing: $command_string"
    rotate_log_if_needed "$AIRUPNP_LOG"
    nohup "${COMMAND_ARGS[@]}" > "$AIRUPNP_LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$AIRUPNP_PID"
    log "AirUPnP started with PID: $pid"
    
    # Verify startup with timeout
    local count=0
    local max_wait=10
    while [[ $count -lt $max_wait ]]; do
        if is_running "$AIRUPNP_PID"; then
            log "AirUPnP started successfully (PID: $pid)"
            AIRUPNP_RESTART_COUNT=0
            return 0
        fi
        sleep 1
        ((count++))
        log_debug "Waiting for AirUPnP to start... ($count/$max_wait)"
    done
    
    log_error "Failed to start AirUPnP - timeout after ${max_wait}s"
    # Check if it was killed by Gatekeeper
    if tail -1 "$AIRUPNP_LOG" 2>/dev/null | grep -q "Killed"; then
        log_error "AirUPnP was killed, possibly by macOS Gatekeeper"
        check_gatekeeper "$AIRUPNP_BIN"
    fi
    # Show last few lines of log for debugging
    log_error "Last 5 lines of AirUPnP log:"
    tail -5 "$AIRUPNP_LOG" 2>/dev/null | while read line; do
        log_error "  $line"
    done
    rm -f "$AIRUPNP_PID"
    return 1
}

# Stop a service gracefully
stop_service() {
    local service_name="$1"
    local pid_file="$2"
    local timeout="${3:-10}"
    
    if ! is_running "$pid_file"; then
        log "$service_name is not running"
        rm -f "$pid_file"
        return 0
    fi
    
    local pid
    pid=$(cat "$pid_file")
    log "Stopping $service_name (PID: $pid)..."
    
    # Try graceful shutdown first
    if kill -TERM "$pid" 2>/dev/null; then
        # Wait for graceful shutdown
        local count=0
        while is_running "$pid_file" && [[ $count -lt $timeout ]]; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if is_running "$pid_file"; then
            log "Graceful shutdown failed, force killing $service_name..."
            kill -KILL "$pid" 2>/dev/null || true
            sleep 1
        fi
    fi
    
    # Clean up PID file
    rm -f "$pid_file"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log "$service_name stopped successfully"
        return 0
    else
        log_error "Failed to stop $service_name"
        return 1
    fi
}

# Health check and restart logic
health_check() {
    local restart_needed=false
    
    # Check AirCast
    if ! is_running "$AIRCAST_PID"; then
        if [[ $AIRCAST_RESTART_COUNT -lt $MAX_RESTART_ATTEMPTS ]]; then
            ((AIRCAST_RESTART_COUNT++))
            log_error "AirCast service died (attempt $AIRCAST_RESTART_COUNT/$MAX_RESTART_ATTEMPTS), restarting..."
            sleep "$RESTART_DELAY"
            if ! start_aircast; then
                log_error "Failed to restart AirCast (attempt $AIRCAST_RESTART_COUNT)"
            fi
        else
            log_error "AirCast has failed $MAX_RESTART_ATTEMPTS times, giving up"
            restart_needed=true
        fi
    fi
    
    # Check AirUPnP
    if ! is_running "$AIRUPNP_PID"; then
        if [[ $AIRUPNP_RESTART_COUNT -lt $MAX_RESTART_ATTEMPTS ]]; then
            ((AIRUPNP_RESTART_COUNT++))
            log_error "AirUPnP service died (attempt $AIRUPNP_RESTART_COUNT/$MAX_RESTART_ATTEMPTS), restarting..."
            sleep "$RESTART_DELAY"
            if ! start_airupnp; then
                log_error "Failed to restart AirUPnP (attempt $AIRUPNP_RESTART_COUNT)"
            fi
        else
            log_error "AirUPnP has failed $MAX_RESTART_ATTEMPTS times, giving up"
            restart_needed=true
        fi
    fi
    
    # If too many failures, exit to let system service manager handle it
    if [[ "$restart_needed" == "true" ]]; then
        log_error "Too many service failures, exiting..."
        cleanup
        exit 1
    fi
}

# Cleanup function for signal handling
cleanup() {
    log "Received termination signal, shutting down services..."
    stop_service "AirCast" "$AIRCAST_PID"
    stop_service "AirUPnP" "$AIRUPNP_PID"
    rm -f "$SERVICE_PID"
    log "AirConnect service manager stopped"
}

# Signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Main service function
main() {
    # Record our PID
    echo $$ > "$SERVICE_PID"
    
    log "AirConnect service manager starting (version 1.0.1)"
    log "Service manager PID: $$"
    log "Configuration file: $CONFIG_FILE"
    log "Configuration loaded: $([[ $CONFIG_LOADED -eq 1 ]] && printf 'yes' || printf 'no')"
    log "Log directory: $LOG_DIR"
    log "PID directory: $PID_DIR"
    log "Health check interval: ${HEALTH_CHECK_INTERVAL}s"
    
    # Start both services
    local start_errors=0
    
    if ! start_aircast; then
        ((start_errors++))
    fi
    
    if ! start_airupnp; then
        ((start_errors++))
    fi
    
    if [[ $start_errors -gt 0 ]]; then
        log_error "Failed to start $start_errors service(s)"
        log_error "If you see Gatekeeper errors, try reinstalling:"
        log_error "  brew uninstall airconnect && brew install airconnect"
        cleanup
        exit 1
    fi
    
    log "All AirConnect services started successfully"
    log "Monitoring services for health..."
    
    # Monitor services and restart if needed
    while true; do
        sleep "$HEALTH_CHECK_INTERVAL"
        health_check
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
