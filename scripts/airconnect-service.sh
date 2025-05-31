#!/bin/bash

# AirConnect Service Manager
# Manages both AirCast and AirUPnP services as a unified service
# Version: 1.0.1
# Author: dmego
# License: MIT

set -euo pipefail

# Source configuration if available
CONFIG_FILE="${HOME}/.config/airconnect/airconnect.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Default configuration
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
AIRCAST_BIN="${AIRCAST_BIN:-$HOMEBREW_PREFIX/bin/aircast}"
AIRUPNP_BIN="${AIRUPNP_BIN:-$HOMEBREW_PREFIX/bin/airupnp}"
LOG_DIR="${LOG_DIR:-$HOMEBREW_PREFIX/var/log}"
PID_DIR="${PID_DIR:-$HOMEBREW_PREFIX/var/run}"
SERVICE_NAME="${SERVICE_NAME:-airconnect}"

# Service configuration
AIRCAST_ARGS="${AIRCAST_ARGS:--d all=info}"
AIRUPNP_ARGS="${AIRUPNP_ARGS:--d all=info}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
RESTART_DELAY="${RESTART_DELAY:-5}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-3}"

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

# Ensure required directories exist
mkdir -p "$LOG_DIR" "$PID_DIR"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SERVICE_NAME] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SERVICE_NAME] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SERVICE_NAME] DEBUG: $*" | tee -a "$LOG_FILE"
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
    
    # Check if file has quarantine attribute
    if xattr -l "$binary" 2>/dev/null | grep -q "com.apple.quarantine"; then
        log_error "$binary_name is quarantined by macOS Gatekeeper"
        log_error "Run: xattr -d com.apple.quarantine $binary"
        return 1
    fi
    
    # Try to execute binary with --help to test if it's blocked
    if ! "$binary" --help >/dev/null 2>&1; then
        local exit_code=$?
        if [[ $exit_code -eq 137 ]]; then  # SIGKILL (Killed: 9)
            log_error "$binary_name was killed by macOS Gatekeeper (exit code 137)"
            log_error "This usually means the binary is unsigned or blocked by security settings"
            log_error "Solutions:"
            log_error "1. Remove quarantine: xattr -d com.apple.quarantine $binary"
            log_error "2. Allow in Security & Privacy settings"
            log_error "3. Reinstall with: brew reinstall airconnect"
            return 1
        fi
    fi
    
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
    nohup $AIRCAST_BIN $AIRCAST_ARGS > "$AIRCAST_LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$AIRCAST_PID"
    
    # Verify startup
    sleep 2
    if is_running "$AIRCAST_PID"; then
        log "AirCast started successfully (PID: $pid)"
        AIRCAST_RESTART_COUNT=0
        return 0
    else
        log_error "Failed to start AirCast"
        # Check if it was killed by Gatekeeper
        if tail -1 "$AIRCAST_LOG" 2>/dev/null | grep -q "Killed"; then
            log_error "AirCast was killed, possibly by macOS Gatekeeper"
            check_gatekeeper "$AIRCAST_BIN"
        fi
        rm -f "$AIRCAST_PID"
        return 1
    fi
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
    nohup $AIRUPNP_BIN $AIRUPNP_ARGS > "$AIRUPNP_LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$AIRUPNP_PID"
    
    # Verify startup
    sleep 2
    if is_running "$AIRUPNP_PID"; then
        log "AirUPnP started successfully (PID: $pid)"
        AIRUPNP_RESTART_COUNT=0
        return 0
    else
        log_error "Failed to start AirUPnP"
        # Check if it was killed by Gatekeeper
        if tail -1 "$AIRUPNP_LOG" 2>/dev/null | grep -q "Killed"; then
            log_error "AirUPnP was killed, possibly by macOS Gatekeeper"
            check_gatekeeper "$AIRUPNP_BIN"
        fi
        rm -f "$AIRUPNP_PID"
        return 1
    fi
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

# Start main function
main "$@"