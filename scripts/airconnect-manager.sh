#!/bin/bash

# AirConnect Management Tool
# Provides convenient commands for managing AirConnect services
# Version: 1.0.0
# Author: dmego
# License: MIT

set -euo pipefail

# Configuration
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
CONFIG_DIR="${HOME}/.config/airconnect"
CONFIG_FILE="$CONFIG_DIR/airconnect.conf"
LOG_DIR="$HOMEBREW_PREFIX/var/log"
PID_DIR="$HOMEBREW_PREFIX/var/run"

# Version info
VERSION="1.0.0"
AIRCONNECT_VERSION="1.8.3"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
print_status() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $*"
}

# Check if service is running
check_service_status() {
    local service="$1"
    local pid_file="$PID_DIR/$service.pid"
    
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        local pid=$(cat "$pid_file")
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "unknown")
        echo -e "${GREEN}Running${NC} (PID: $pid, uptime: $uptime)"
        return 0
    else
        echo -e "${RED}Stopped${NC}"
        return 1
    fi
}

# Show comprehensive status
show_status() {
    print_info "AirConnect Service Status"
    echo "=========================="
    echo ""
    
    printf "%-20s: " "Service Manager"
    check_service_status "airconnect" || true
    
    printf "%-20s: " "AirCast"
    check_service_status "aircast" || true
    
    printf "%-20s: " "AirUPnP"
    check_service_status "airupnp" || true
    
    echo ""
    
    # Check Homebrew service status
    print_info "Homebrew Service Status:"
    if command -v brew >/dev/null 2>&1; then
        brew services list | grep airconnect || print_warning "AirConnect not found in brew services"
    else
        print_error "Homebrew not found"
    fi
    
    echo ""
    print_info "System Information:"
    echo "  Log directory: $LOG_DIR"
    echo "  PID directory: $PID_DIR"
    echo "  Config file: $CONFIG_FILE"
    echo "  Manager version: $VERSION"
    echo "  AirConnect version: $AIRCONNECT_VERSION"
    
    # Check log file sizes
    echo ""
    print_info "Log File Sizes:"
    for log in airconnect-service aircast airupnp; do
        local log_file="$LOG_DIR/$log.log"
        if [[ -f "$log_file" ]]; then
            local size=$(du -h "$log_file" | cut -f1)
            echo "  $log: $size"
        else
            echo "  $log: not found"
        fi
    done
}

# Show logs with options
show_logs() {
    local service="${1:-all}"
    local lines="${2:-50}"
    local follow="${3:-false}"
    
    case "$service" in
        aircast)
            print_info "AirCast logs (last $lines lines):"
            echo "================================="
            if [[ "$follow" == "true" ]]; then
                tail -f -n "$lines" "$LOG_DIR/aircast.log" 2>/dev/null || print_error "Cannot access AirCast logs"
            else
                tail -n "$lines" "$LOG_DIR/aircast.log" 2>/dev/null || print_error "No AirCast logs found"
            fi
            ;;
        airupnp)
            print_info "AirUPnP logs (last $lines lines):"
            echo "================================="
            if [[ "$follow" == "true" ]]; then
                tail -f -n "$lines" "$LOG_DIR/airupnp.log" 2>/dev/null || print_error "Cannot access AirUPnP logs"
            else
                tail -n "$lines" "$LOG_DIR/airupnp.log" 2>/dev/null || print_error "No AirUPnP logs found"
            fi
            ;;
        service)
            print_info "Service manager logs (last $lines lines):"
            echo "========================================="
            if [[ "$follow" == "true" ]]; then
                tail -f -n "$lines" "$LOG_DIR/airconnect-service.log" 2>/dev/null || print_error "Cannot access service logs"
            else
                tail -n "$lines" "$LOG_DIR/airconnect-service.log" 2>/dev/null || print_error "No service logs found"
            fi
            ;;
        all|*)
            if [[ "$follow" == "true" ]]; then
                print_info "Following all AirConnect logs (Ctrl+C to stop)..."
                tail -f "$LOG_DIR"/airconnect*.log "$LOG_DIR"/air*.log 2>/dev/null || print_error "Cannot follow logs"
            else
                for log_type in service aircast airupnp; do
                    local log_file="$LOG_DIR/airconnect-$log_type.log"
                    [[ "$log_type" != "service" ]] && log_file="$LOG_DIR/$log_type.log"
                    
                    if [[ -f "$log_file" ]]; then
                        print_info "${log_type^} logs (last 20 lines):"
                        echo "$(printf '=%.0s' {1..40})"
                        tail -n 20 "$log_file"
                        echo ""
                    fi
                done
            fi
            ;;
    esac
}

# Configuration management
manage_config() {
    local action="${1:-edit}"
    
    case "$action" in
        edit)
            # Create config directory if it doesn't exist
            mkdir -p "$CONFIG_DIR"
            
            # Create default config if it doesn't exist
            if [[ ! -f "$CONFIG_FILE" ]]; then
                create_default_config
            fi
            
            # Open in editor
            local editor="${EDITOR:-nano}"
            if command -v "$editor" >/dev/null 2>&1; then
                "$editor" "$CONFIG_FILE"
            else
                print_error "Editor '$editor' not found. Please set EDITOR environment variable."
                print_info "Available editors: vim, nano, code, etc."
            fi
            ;;
        show)
            if [[ -f "$CONFIG_FILE" ]]; then
                print_info "Current configuration ($CONFIG_FILE):"
                echo "======================================"
                cat "$CONFIG_FILE"
            else
                print_warning "No configuration file found at $CONFIG_FILE"
                print_info "Run 'airconnect config' to create one"
            fi
            ;;
        reset)
            print_warning "This will reset your configuration to defaults."
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                create_default_config
                print_status "Configuration reset to defaults"
            else
                print_info "Configuration reset cancelled"
            fi
            ;;
        *)
            print_error "Unknown config action: $action"
            print_info "Available actions: edit, show, reset"
            ;;
    esac
}

# Create default configuration
create_default_config() {
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_FILE" << 'EOF'
# AirConnect Configuration File
# Edit this file to customize AirConnect behavior

# Service binaries (usually don't need to change these)
AIRCAST_BIN="/opt/homebrew/bin/aircast"
AIRUPNP_BIN="/opt/homebrew/bin/airupnp"

# Log and PID directories
LOG_DIR="/opt/homebrew/var/log"
PID_DIR="/opt/homebrew/var/run"

# Service arguments
# -d all: discover all devices
AIRCAST_ARGS="-d all=info"
AIRUPNP_ARGS="-d all=info"

# Health monitoring
HEALTH_CHECK_INTERVAL="30"  # seconds between health checks
RESTART_DELAY="5"           # seconds to wait before restart
MAX_RESTART_ATTEMPTS="3"    # max restart attempts before giving up

# Debug mode (1 to enable, 0 to disable)
DEBUG="0"

# Custom device exclusions (comma-separated)
# EXCLUDED_DEVICES="device1,device2"

# Network interface (leave empty for auto-detection)
# NETWORK_INTERFACE="en0"
EOF

    print_status "Default configuration created at $CONFIG_FILE"
}

# System diagnostics
run_diagnostics() {
    print_info "AirConnect System Diagnostics"
    echo "============================="
    echo ""
    
    # Check Homebrew
    print_info "Checking Homebrew installation..."
    if command -v brew >/dev/null 2>&1; then
        echo "  ✅ Homebrew found: $(brew --version | head -n1)"
        
        # Check if AirConnect is installed
        if brew list airconnect >/dev/null 2>&1; then
            echo "  ✅ AirConnect installed"
        else
            echo "  ❌ AirConnect not found"
        fi
    else
        echo "  ❌ Homebrew not found"
    fi
    
    # Check binaries
    echo ""
    print_info "Checking AirConnect binaries..."
    for binary in aircast airupnp airconnect-service; do
        if command -v "$binary" >/dev/null 2>&1; then
            echo "  ✅ $binary: $(which "$binary")"
        else
            echo "  ❌ $binary: not found in PATH"
        fi
    done
    
    # Check network connectivity
    echo ""
    print_info "Checking network connectivity..."
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "  ✅ Internet connectivity"
    else
        echo "  ❌ No internet connectivity"
    fi

    
    # Check file permissions
    echo ""
    print_info "Checking file permissions..."
    for dir in "$LOG_DIR" "$PID_DIR" "$CONFIG_DIR"; do
        if [[ -d "$dir" ]]; then
            if [[ -w "$dir" ]]; then
                echo "  ✅ $dir: writable"
            else
                echo "  ❌ $dir: not writable"
            fi
        else
            echo "  ⚠️  $dir: does not exist"
        fi
    done
    
    # Check system resources
    echo ""
    print_info "System resources:"
    echo "  Memory usage: $(ps -A -o %mem | awk '{s+=$1} END {print s "%"}')"
    echo "  Load average: $(uptime | awk -F'load average:' '{ print $2 }')"
    
    echo ""
    print_info "Diagnostics complete"
}

# Show help
show_help() {
    cat << EOF
AirConnect Management Tool v$VERSION

USAGE:
    $(basename "$0") <command> [options]

COMMANDS:
    status              Show detailed service status
    logs [service]      Show logs (all, aircast, airupnp, service)
    follow [service]    Follow logs in real-time
    config [action]     Manage configuration (edit, show, reset)
    diagnostics         Run system diagnostics
    version             Show version information
    help                Show this help message

LOG COMMANDS:
    logs                Show last 50 lines from all logs
    logs aircast        Show AirCast logs only
    logs airupnp        Show AirUPnP logs only  
    logs service        Show service manager logs only
    logs all 100        Show last 100 lines from all logs
    follow              Follow all logs in real-time
    follow aircast      Follow AirCast logs only

CONFIG COMMANDS:
    config              Edit configuration file
    config edit         Edit configuration file
    config show         Display current configuration
    config reset        Reset to default configuration

SERVICE MANAGEMENT:
    Use 'brew services' commands to control the service:
    
    brew services start airconnect      # Start AirConnect
    brew services stop airconnect       # Stop AirConnect  
    brew services restart airconnect    # Restart AirConnect
    brew services list                  # List all services

EXAMPLES:
    $(basename "$0") status
    $(basename "$0") logs aircast
    $(basename "$0") follow service
    $(basename "$0") config edit
    $(basename "$0") diagnostics

FILES:
    Configuration: $CONFIG_FILE
    Service logs:  $LOG_DIR/airconnect-service.log
    AirCast logs:  $LOG_DIR/aircast.log
    AirUPnP logs:  $LOG_DIR/airupnp.log

EOF
}

# Show version information
show_version() {
    cat << EOF
AirConnect Management Tool
Version: $VERSION
AirConnect Version: $AIRCONNECT_VERSION

Components:
  • AirCast  - Streams to Chromecast devices
  • AirUPnP  - Streams to UPnP/Sonos devices

Repository: https://github.com/dmego/homebrew-airconnect
Upstream:   https://github.com/philippe44/AirConnect

Copyright (c) 2025 dmego
License: MIT
EOF
}

# Main function
main() {
    case "${1:-help}" in
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-all}" "${3:-50}" false
            ;;
        follow)
            show_logs "${2:-all}" "${3:-50}" true
            ;;
        config)
            manage_config "${2:-edit}"
            ;;
        diagnostics|diag)
            run_diagnostics
            ;;
        version)
            show_version
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: ${1:-}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"