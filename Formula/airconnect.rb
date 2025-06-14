class Airconnect < Formula
  desc "Use AirPlay to stream to UPnP/Sonos & Chromecast devices"
  homepage "https://github.com/philippe44/AirConnect"
  url "https://github.com/philippe44/AirConnect/releases/download/1.8.3/AirConnect-1.8.3.zip"
  sha256 "f103595c522b0a4eeca8cb02301a35005d069d4298991ae82e9c312ddb7c8270"
  license "MIT"

  livecheck do
    url :stable
    strategy :github_latest
  end

  def install
    # Determine architecture-specific binary names
    arch_suffix = Hardware::CPU.arm? ? "arm64" : "x86_64"
    
    # Install the main binaries
    bin.install "aircast-macos-#{arch_suffix}-static" => "aircast"
    bin.install "airupnp-macos-#{arch_suffix}-static" => "airupnp"

    # Create necessary directories
    (var/"log").mkpath
    (var/"run").mkpath
    (var/"lib/airconnect").mkpath

    # Download and prepare support scripts
    support_dir = buildpath/"support"
    support_dir.mkpath

    # Download scripts from your repository
    base_url = "https://raw.githubusercontent.com/dmego/homebrew-airconnect/main"
    
    [
      ["airconnect-service.sh", "scripts/airconnect-service.sh"],
      ["airconnect-manager.sh", "scripts/airconnect-manager.sh"],
      ["airconnect.conf", "configs/airconnect.conf"]
    ].each do |target, source|
      begin
        system "curl", "-L", "-s", "-f", "-o", support_dir/target, "#{base_url}/#{source}"
      rescue => e
        ohai "Could not download #{target}: #{e.message}"
        # Create minimal fallback files if download fails
        case target
        when "airconnect-service.sh"
          (support_dir/target).write(<<~SCRIPT)
            #!/bin/bash
            # AirConnect Service Script
            set -e
            
            HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-#{HOMEBREW_PREFIX}}"
            AIRCAST_BIN="${HOMEBREW_PREFIX}/bin/aircast"
            AIRUPNP_BIN="${HOMEBREW_PREFIX}/bin/airupnp"
            
            # Default arguments
            AIRCAST_ARGS="-d all=info"
            AIRUPNP_ARGS="-d all=info"
            
            # Load config if exists
            if [ -f "#{etc}/airconnect/airconnect.conf" ]; then
              source "#{etc}/airconnect/airconnect.conf"
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
            
            HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-#{HOMEBREW_PREFIX}}"
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
                config_file="#{etc}/airconnect/airconnect.conf"
                if [ ! -f "$config_file" ]; then
                  mkdir -p "$(dirname "$config_file")"
                  echo "# AirConnect Configuration" > "$config_file"
                  echo "AIRCAST_ARGS=\\"-d all=info\\"" >> "$config_file"
                  echo "AIRUPNP_ARGS=\\"-d all=info\\"" >> "$config_file"
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
            AIRCAST_ARGS="-d all=info"
            
            # Arguments for AirUPnP (UPnP/Sonos support)
            AIRUPNP_ARGS="-d all=info"
            
            # For more options, see:
            # https://github.com/philippe44/AirConnect
          CONFIG
        end
      end
    end

    # Make scripts executable
    (support_dir/"airconnect-service.sh").chmod(0755) if (support_dir/"airconnect-service.sh").exist?
    (support_dir/"airconnect-manager.sh").chmod(0755) if (support_dir/"airconnect-manager.sh").exist?

    # Install the service wrapper and management tool
    bin.install support_dir/"airconnect-service.sh" => "airconnect-service"
    bin.install support_dir/"airconnect-manager.sh" => "airconnect"
    
    # Store default configuration template in var/lib for later use
    (var/"lib/airconnect").install support_dir/"airconnect.conf" => "airconnect.conf.default"

    # Remove quarantine attributes to prevent Gatekeeper issues
    [
      bin/"aircast",
      bin/"airupnp",
      bin/"airconnect-service"
    ].each do |binary|
      if binary.exist?
        # Use shell redirection to suppress errors
        system "xattr -d com.apple.quarantine '#{binary}' 2>/dev/null || true"
      end
    end
  end

  def uninstall
    ohai "Uninstalling AirConnect..."
    
    # Stop the service using launchctl directly since brew command might not be available
    plist_path = "#{ENV["HOME"]}/Library/LaunchAgents/homebrew.mxcl.airconnect.plist"
    if File.exist?(plist_path)
      ohai "Stopping service via launchctl..."
      system "launchctl unload '#{plist_path}' 2>/dev/null || true"
    end
    
    # Also try to stop processes directly
    ohai "Stopping any running AirConnect processes..."
    system "pkill -f 'aircast|airupnp|airconnect' 2>/dev/null || true"
    
    # Get proper paths using HOMEBREW_PREFIX
    homebrew_prefix = ENV["HOMEBREW_PREFIX"] || HOMEBREW_PREFIX
    
    # Manually clean up configuration files with absolute paths
    config_paths = [
      "#{homebrew_prefix}/etc/airconnect",
      "#{homebrew_prefix}/var/lib/airconnect"
    ]
    
    config_paths.each do |path|
      if File.exist?(path) || Dir.exist?(path)
        ohai "Removing configuration: #{path}"
        begin
          # Use system command for better error handling
          system "rm -rf '#{path}'" 
          ohai "Successfully removed: #{path}"
        rescue => e
          opoo "Failed to remove #{path}: #{e.message}"
        end
      else
        ohai "Configuration path not found (skipping): #{path}"
      end
    end
    
    # Call comprehensive cleanup method
    cleanup_on_uninstall
  end

  def cleanup_on_uninstall
    ohai "Cleaning up AirConnect files and directories..."
    
    # Get proper paths
    homebrew_prefix = ENV["HOMEBREW_PREFIX"] || HOMEBREW_PREFIX
    etc_dir = "#{homebrew_prefix}/etc"
    var_dir = "#{homebrew_prefix}/var"
    
    # Complete cleanup similar to zap functionality
    cleanup_paths = [
      # Configuration files and directory
      "#{etc_dir}/airconnect",
      
      # Data and library files
      "#{var_dir}/lib/airconnect",
      
      # Log files
      "#{var_dir}/log/aircast.log",
      "#{var_dir}/log/airupnp.log", 
      "#{var_dir}/log/airconnect-service.log",
      "#{var_dir}/log/airconnect.log",
      
      # PID files
      "#{var_dir}/run/aircast.pid",
      "#{var_dir}/run/airupnp.pid",
      "#{var_dir}/run/airconnect.pid",
      "#{var_dir}/run/airconnect-service.pid",
      
      # LaunchAgent plist file
      "#{ENV["HOME"]}/Library/LaunchAgents/homebrew.mxcl.airconnect.plist",
      
      # User configuration directory (if exists)
      "#{ENV["HOME"]}/.config/airconnect"
    ]
    
    cleanup_paths.each do |path|
      if File.exist?(path) || Dir.exist?(path)
        ohai "Removing: #{path}"
        begin
          # Use system command for better error handling and permissions
          if Dir.exist?(path)
            system "rm -rf '#{path}'"
          else
            system "rm -f '#{path}'"
          end
          ohai "Successfully removed: #{path}"
        rescue => e
          opoo "Failed to remove #{path}: #{e.message}"
        end
      else
        ohai "Not found (skipping): #{path}"
      end
    end
    
    # Clean up any remaining airconnect-related files in log and run directories
    ["#{var_dir}/log", "#{var_dir}/run"].each do |dir|
      if Dir.exist?(dir)
        ohai "Checking directory for remaining files: #{dir}"
        
        # Use system find command for better glob handling
        system "find '#{dir}' -name 'airconnect*' -delete 2>/dev/null || true"
        system "find '#{dir}' -name 'air*.log' -delete 2>/dev/null || true"
        system "find '#{dir}' -name 'air*.pid' -delete 2>/dev/null || true"
      end
    end
    
    ohai "AirConnect cleanup completed!"
  end

  def post_install
    ohai "AirConnect installation completed!"
    
    # Create configuration file in Homebrew's etc directory
    begin
      config_dir = etc/"airconnect"
      config_file = config_dir/"airconnect.conf"
      template_file = var/"lib/airconnect/airconnect.conf.default"
      
      ohai "Creating configuration directory at #{config_dir}"
      config_dir.mkpath
      
      # Copy template to config if template exists
      if template_file.exist?
        ohai "Copying configuration template to #{config_file}"
        config_file.write(template_file.read)
      else
        # Create default config directly
        ohai "Creating default configuration at #{config_file}"
        config_file.write(<<~CONFIG)
          # AirConnect Configuration File
          # Edit this file to customize AirConnect behavior
          
          # Service binaries (usually don't need to change these)
          AIRCAST_BIN="#{bin}/aircast"
          AIRUPNP_BIN="#{bin}/airupnp"
          
          # Log and PID directories
          LOG_DIR="#{var}/log"
          PID_DIR="#{var}/run"
          
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
        CONFIG
      end
      
      # Ensure proper permissions
      config_file.chmod(0644)
      ohai "Configuration file created successfully at #{config_file}"
      
    rescue => e
      opoo "Could not create configuration file: #{e.message}"
      ohai "Configuration will be created when you first run 'airconnect config'"
    end
    
    # Create version file more safely
    begin
      version_file = var/"lib/airconnect/VERSION"
      version_file.write(version.to_s)
    rescue
      # Ignore version file creation errors
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
        aircast -d all=info                   # Start AirCast manually
        airupnp -d all=info                   # Start AirUPnP manually
      
      FEATURES:
        ✅ Automatic service management with Homebrew services
        ✅ Detailed logging for troubleshooting
        ✅ Unified control of both AirCast and AirUPnP
        ✅ Configuration file support
        ✅ Automatic Gatekeeper bypass
      
      MANAGEMENT:
        Use 'airconnect help' for detailed usage information
        Config file: #{etc}/airconnect/airconnect.conf
        Log files: #{ENV["HOMEBREW_PREFIX"] || HOMEBREW_PREFIX}/var/log/
      
      SERVICES:
        🎵 AirCast  - Streams to Chromecast devices
        🔊 AirUPnP  - Streams to UPnP/Sonos devices
      
      TROUBLESHOOTING:
        If 'brew services start airconnect' fails, try:
        1. Check service status: brew services list | grep airconnect
        2. Run manually: airconnect-service
        3. Check logs: airconnect logs
        4. Remove quarantine manually: 
           xattr -d com.apple.quarantine #{bin}/aircast
           xattr -d com.apple.quarantine #{bin}/airupnp
      
      DOCUMENTATION:
        README: https://github.com/dmego/homebrew-airconnect/blob/main/README.md
        中文说明: https://github.com/dmego/homebrew-airconnect/blob/main/README_zh.md
      
    EOS
  end

  service do
    run opt_bin/"airconnect-service"
    keep_alive true
    log_path var/"log/airconnect-service.log"
    error_log_path var/"log/airconnect-service.log"
    working_dir var
    process_type :background
    environment_variables PATH: std_service_path_env
  end

  def caveats
    <<~EOS
      To start airconnect now and restart at login:
        brew services start airconnect
      
      Or, if you don't want/need a background service you can just run:
        airconnect-service
      
      Configuration file is located at:
        #{etc}/airconnect/airconnect.conf
      
      Log files are located at:
        #{var}/log/airconnect-service.log
        #{var}/log/aircast.log
        #{var}/log/airupnp.log
    EOS
  end

  test do
    # Test that binaries are executable and show version/help
    # Note: AirConnect binaries may return non-zero exit codes for --help
    system bin/"aircast", "--help"
    system bin/"airupnp", "--help"
    
    # Test that management script is available and executable
    assert_predicate bin/"airconnect", :exist?
    assert_predicate bin/"airconnect", :executable?
    assert_predicate bin/"airconnect-service", :exist?
    assert_predicate bin/"airconnect-service", :executable?
    
    # Test default configuration template
    assert_predicate var/"lib/airconnect/airconnect.conf.default", :exist?
    
    # Test that help command works
    output = shell_output("#{bin}/airconnect help")
    assert_match "AirConnect Manager", output
  end

  # Thorough cleanup for users who want to completely remove all traces
  # Note: Use 'brew uninstall --zap airconnect' to perform complete cleanup
  def zap
    ohai "Performing thorough cleanup of all AirConnect files..."
    
    # Get proper paths
    homebrew_prefix = ENV["HOMEBREW_PREFIX"] || HOMEBREW_PREFIX
    
    # All cleanup paths with proper error handling
    zap_paths = [
      # Configuration directories
      "#{homebrew_prefix}/etc/airconnect",
      "#{Dir.home}/.config/airconnect",
      
      # Data and cache directories  
      "#{homebrew_prefix}/var/lib/airconnect",
      "#{Dir.home}/Library/Caches/airconnect",
      "#{Dir.home}/Library/Application Support/airconnect",
      
      # Log files
      "#{homebrew_prefix}/var/log/aircast.log",
      "#{homebrew_prefix}/var/log/airupnp.log",
      "#{homebrew_prefix}/var/log/airconnect-service.log",
      "#{homebrew_prefix}/var/log/airconnect.log",
      
      # PID files
      "#{homebrew_prefix}/var/run/aircast.pid",
      "#{homebrew_prefix}/var/run/airupnp.pid",
      "#{homebrew_prefix}/var/run/airconnect.pid",
      "#{homebrew_prefix}/var/run/airconnect-service.pid",
      
      # LaunchAgent files
      "#{Dir.home}/Library/LaunchAgents/homebrew.mxcl.airconnect.plist",
      "#{Dir.home}/Library/LaunchAgents/airconnect.plist",
      
      # Preferences
      "#{Dir.home}/Library/Preferences/airconnect.plist",
      "#{Dir.home}/Library/Saved Application State/airconnect.savedState"
    ]
    
    zap_paths.each do |path|
      if File.exist?(path) || Dir.exist?(path)
        ohai "Removing: #{path}"
        begin
          # Use system command for better permissions handling
          if Dir.exist?(path)
            system "rm -rf '#{path}'"
          else
            system "rm -f '#{path}'"
          end
          ohai "Successfully removed: #{path}"
        rescue => e
          opoo "Failed to remove #{path}: #{e.message}"
        end
      else
        ohai "Not found (skipping): #{path}"
      end
    end
    
    # Clean up any remaining processes
    ohai "Stopping any remaining AirConnect processes..."
    system "pkill -f 'airconnect|aircast|airupnp' 2>/dev/null || true"
    
    # Clean up glob patterns
    glob_patterns = [
      "#{homebrew_prefix}/var/log/air*.log",
      "#{homebrew_prefix}/var/run/air*.pid",
      "/tmp/airconnect*",
      "/var/log/airconnect*"
    ]
    
    glob_patterns.each do |pattern|
      ohai "Cleaning up pattern: #{pattern}"
      system "find #{File.dirname(pattern)} -name '#{File.basename(pattern)}' -delete 2>/dev/null || true"
    end
    
    ohai "Complete AirConnect cleanup finished!"
  end
end
