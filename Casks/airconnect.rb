cask "airconnect" do
  arch arm: "arm64", intel: "x86_64"

  version "1.8.3"
  sha256 "f103595c522b0a4eeca8cb02301a35005d069d4298991ae82e9c312ddb7c8270"

  url "https://github.com/philippe44/AirConnect/releases/download/#{version}/AirConnect-#{version}.zip"
  name "AirConnect"
  desc "Use AirPlay to stream to UPnP/Sonos & Chromecast devices"
  homepage "https://github.com/philippe44/AirConnect"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  # Install individual binaries for direct access
  binary "aircast-macos-#{arch}-static", target: "aircast"
  binary "airupnp-macos-#{arch}-static", target: "airupnp"

  # Download and prepare support scripts
  preflight do
    support_dir = staged_path/"support"
    support_dir.mkpath

    # Download scripts from your repository
    base_url = "https://raw.githubusercontent.com/dmego/homebrew-airconnect/main"
    
    [
      ["airconnect-service.sh", "scripts/airconnect-service.sh"],
      ["airconnect-manager.sh", "scripts/airconnect-manager.sh"],
      ["airconnect.conf", "configs/airconnect.conf"]
    ].each do |target, source|
      begin
        system_command "curl", 
          args: ["-L", "-s", "-f", "-o", support_dir/target, "#{base_url}/#{source}"],
          print_stderr: false
      rescue => e
        opoo "Could not download #{target}: #{e.message}"
        # Create minimal fallback files if download fails
        case target
        when "airconnect-service.sh"
          (support_dir/target).write(<<~SCRIPT)
            #!/bin/bash
            # AirConnect Service Script
            set -e
            
            HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
            AIRCAST_BIN="${HOMEBREW_PREFIX}/bin/aircast"
            AIRUPNP_BIN="${HOMEBREW_PREFIX}/bin/airupnp"
            
            # Default arguments
            AIRCAST_ARGS="-d all -l 1000"
            AIRUPNP_ARGS="-d all -l 1000"
            
            # Load config if exists
            if [ -f "$HOME/.config/airconnect/airconnect.conf" ]; then
              source "$HOME/.config/airconnect/airconnect.conf"
            fi
            
            echo "Starting AirConnect services..."
            echo "AirCast: $AIRCAST_BIN $AIRCAST_ARGS"
            echo "AirUPnP: $AIRUPNP_BIN $AIRUPNP_ARGS"
            
            # Start both services
            exec "$AIRCAST_BIN" $AIRCAST_ARGS &
            AIRCAST_PID=$!
            exec "$AIRUPNP_BIN" $AIRUPNP_ARGS &
            AIRUPNP_PID=$!
            
            # Wait for both processes
            wait $AIRCAST_PID $AIRUPNP_PID
          SCRIPT
        when "airconnect-manager.sh"
          (support_dir/target).write(<<~SCRIPT)
            #!/bin/bash
            # AirConnect Manager Script
            
            HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
            SERVICE_NAME="homebrew.mxcl.airconnect"
            
            case "$1" in
              start)
                echo "Starting AirConnect service..."
                brew services start airconnect
                ;;
              stop)
                echo "Stopping AirConnect service..."
                brew services stop airconnect
                ;;
              restart)
                echo "Restarting AirConnect service..."
                brew services restart airconnect
                ;;
              status)
                echo "AirConnect service status:"
                brew services list | grep airconnect || echo "Service not found"
                ;;
              logs)
                echo "AirConnect service logs:"
                if [ -f "${HOMEBREW_PREFIX}/var/log/airconnect-service.log" ]; then
                  tail -f "${HOMEBREW_PREFIX}/var/log/airconnect-service.log"
                else
                  echo "Log file not found at ${HOMEBREW_PREFIX}/var/log/airconnect-service.log"
                fi
                ;;
              config)
                config_file="$HOME/.config/airconnect/airconnect.conf"
                if [ ! -f "$config_file" ]; then
                  mkdir -p "$(dirname "$config_file")"
                  echo "# AirConnect Configuration" > "$config_file"
                  echo "AIRCAST_ARGS=\"-d all -l 1000\"" >> "$config_file"
                  echo "AIRUPNP_ARGS=\"-d all -l 1000\"" >> "$config_file"
                fi
                ${EDITOR:-nano} "$config_file"
                ;;
              help|*)
                echo "AirConnect Manager"
                echo "Usage: $0 {start|stop|restart|status|logs|config|help}"
                echo ""
                echo "Commands:"
                echo "  start   - Start AirConnect service"
                echo "  stop    - Stop AirConnect service"
                echo "  restart - Restart AirConnect service"
                echo "  status  - Show service status"
                echo "  logs    - Show service logs"
                echo "  config  - Edit configuration file"
                echo "  help    - Show this help message"
                ;;
            esac
          SCRIPT
        when "airconnect.conf"
          (support_dir/target).write(<<~CONFIG)
            # AirConnect Configuration
            # Arguments for AirCast (Chromecast support)
            AIRCAST_ARGS="-d all -l 1000"
            
            # Arguments for AirUPnP (UPnP/Sonos support)
            AIRUPNP_ARGS="-d all -l 1000"
            
            # For more options, see:
            # https://github.com/philippe44/AirConnect
          CONFIG
        end
      end
    end

    # Make scripts executable
    (support_dir/"airconnect-service.sh").chmod(0755) if (support_dir/"airconnect-service.sh").exist?
    (support_dir/"airconnect-manager.sh").chmod(0755) if (support_dir/"airconnect-manager.sh").exist?
  end

  # Install the service wrapper and management tool
  binary "support/airconnect-service.sh", target: "airconnect-service"
  binary "support/airconnect-manager.sh", target: "airconnect"

  # Install configuration and version info
  preflight do
    # Create config directory
    config_dir = Pathname("#{Dir.home}/.config/airconnect")
    config_dir.mkpath
    
    # Install default config if it doesn't exist
    config_file = config_dir/"airconnect.conf"
    unless config_file.exist?
      if (staged_path/"support/airconnect.conf").exist?
        system_command "cp", args: [staged_path/"support/airconnect.conf", config_file]
      end
    end
    
    # Store version info
    version_dir = Pathname("#{HOMEBREW_PREFIX}/var/lib/airconnect")
    version_dir.mkpath
    
    version_file = version_dir/"VERSION"
    version_file.write(version)
  end

  # Service configuration for Homebrew services
  service do
    name "homebrew.mxcl.airconnect"
    run opt_bin/"airconnect-service"
    keep_alive true
    log_path "#{HOMEBREW_PREFIX}/var/log/airconnect-service.log"
    error_log_path "#{HOMEBREW_PREFIX}/var/log/airconnect-service.log"
    working_dir "#{HOMEBREW_PREFIX}/var"
    process_type :background
  end

  # Post-installation message and quarantine removal
  postflight do
    # Remove quarantine attributes from binaries to prevent Gatekeeper issues
    [
      "#{HOMEBREW_PREFIX}/bin/aircast",
      "#{HOMEBREW_PREFIX}/bin/airupnp",
      "#{HOMEBREW_PREFIX}/bin/airconnect-service"
    ].each do |binary|
      if File.exist?(binary)
        begin
          system_command "xattr", args: ["-d", "com.apple.quarantine", binary], sudo: false
        rescue
          # Ignore errors if attribute doesn't exist
        end
      end
    end

    puts <<~EOS
      
      🎉 AirConnect has been successfully installed!
      
      INSTALLED VERSION: #{version}
      
      🔒 SECURITY NOTE: 
      Quarantine attributes have been automatically removed from AirConnect binaries
      to prevent macOS Gatekeeper issues.
      
      QUICK START:
        brew services start airconnect    # Start the service
        airconnect status                # Check service status
        airconnect logs                  # View logs
        airconnect config                # Edit configuration
      
      MANUAL USAGE:
        aircast -d all                   # Start AirCast manually
        airupnp -d all                   # Start AirUPnP manually
      
      FEATURES:
        ✅ Automatic service management with Homebrew services
        ✅ Detailed logging for troubleshooting
        ✅ Unified control of both AirCast and AirUPnP
        ✅ Configuration file support
        ✅ Automatic Gatekeeper bypass
      
      MANAGEMENT:
        Use 'airconnect help' for detailed usage information
        Config file: ~/.config/airconnect/airconnect.conf
        Log files: #{HOMEBREW_PREFIX}/var/log/
      
      SERVICES:
        🎵 AirCast  - Streams to Chromecast devices
        🔊 AirUPnP  - Streams to UPnP/Sonos devices
      
      TROUBLESHOOTING:
        If 'brew services start airconnect' fails, try:
        1. Check service status: brew services list | grep airconnect
        2. Run manually: airconnect-service
        3. Check logs: airconnect logs
        4. Remove quarantine manually: 
           xattr -d com.apple.quarantine /opt/homebrew/bin/aircast
           xattr -d com.apple.quarantine /opt/homebrew/bin/airupnp
      
      DOCUMENTATION:
        README: https://github.com/dmego/homebrew-airconnect/blob/main/README.md
        中文说明: https://github.com/dmego/homebrew-airconnect/blob/main/README_zh.md
      
    EOS
  end

  # Cleanup on uninstall
  uninstall_preflight do
    system_command "brew", args: ["services", "stop", "airconnect"], sudo: false
  end

  # Complete cleanup on zap
  zap trash: [
    "#{Dir.home}/.config/airconnect",
    "#{HOMEBREW_PREFIX}/var/lib/airconnect",
    "#{HOMEBREW_PREFIX}/var/log/aircast.log",
    "#{HOMEBREW_PREFIX}/var/log/airupnp.log", 
    "#{HOMEBREW_PREFIX}/var/log/airconnect-service.log",
    "#{HOMEBREW_PREFIX}/var/run/aircast.pid",
    "#{HOMEBREW_PREFIX}/var/run/airupnp.pid",
    "#{HOMEBREW_PREFIX}/var/run/airconnect.pid",
  ]
end