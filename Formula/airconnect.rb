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
                config_file="$HOME/.config/airconnect/airconnect.conf"
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
    # Stop the service using launchctl directly since brew command might not be available
    plist_path = "#{ENV["HOME"]}/Library/LaunchAgents/homebrew.mxcl.airconnect.plist"
    if File.exist?(plist_path)
      system "launchctl unload '#{plist_path}' 2>/dev/null || true"
    end
    
    # Also try to stop processes directly
    system "pkill -f 'aircast|airupnp|airconnect' 2>/dev/null || true"
    
    # Call cleanup method
    cleanup_on_uninstall
  end

  def cleanup_on_uninstall
    # Complete cleanup similar to zap functionality
    cleanup_paths = [
      "#{ENV["HOME"]}/.config/airconnect",
      "#{var}/lib/airconnect",
      "#{var}/log/aircast.log",
      "#{var}/log/airupnp.log", 
      "#{var}/log/airconnect-service.log",
      "#{var}/run/aircast.pid",
      "#{var}/run/airupnp.pid",
      "#{var}/run/airconnect.pid",
    ]
    
    cleanup_paths.each do |path|
      if File.exist?(path) || Dir.exist?(path)
        rm_rf path
      end
    end
  end

  def post_install
    # Create user config directory and copy default config if needed
    begin
      home_dir = ENV["HOME"]
      ohai "🏠 Home directory: #{home_dir}"
      
      config_dir = Pathname.new(home_dir) / ".config" / "airconnect"
      ohai "📁 Target config directory: #{config_dir}"
      
      # Check if directory exists before creating
      if config_dir.exist?
        ohai "✅ Config directory already exists"
      else
        ohai "📂 Creating config directory..."
        config_dir.mkpath
        if config_dir.exist?
          ohai "✅ Config directory created successfully"
        else
          onoe "❌ Failed to create config directory"
        end
      end
      
      user_config = config_dir / "airconnect.conf"
      default_config = var / "lib" / "airconnect" / "airconnect.conf.default"
      
      ohai "🎯 Target config file: #{user_config}"
      ohai "📋 Source template file: #{default_config}"
      
      # Check if source template exists
      if default_config.exist?
        ohai "✅ Source template file exists"
      else
        onoe "❌ Source template file not found!"
        ohai "📝 Creating fallback configuration..."
        
        # Create a basic config directly
        user_config.write(<<~CONFIG)
          # AirConnect Configuration
          # Arguments for AirCast (Chromecast support)
          AIRCAST_ARGS="-d all=info"
          
          # Arguments for AirUPnP (UPnP/Sonos support)
          AIRUPNP_ARGS="-d all=info"
          
          # For more options, see:
          # https://github.com/philippe44/AirConnect
        CONFIG
        ohai "✅ Fallback configuration created"
      end
      
      # Copy config file if it doesn't exist
      if user_config.exist?
        ohai "✅ User config file already exists"
      else
        if default_config.exist?
          ohai "📋 Copying template to user config..."
          cp default_config, user_config
          if user_config.exist?
            ohai "✅ User config file created successfully"
            user_config.chmod(0644)
            ohai "🔐 Set config file permissions to 644"
          else
            onoe "❌ Failed to copy config file"
          end
        end
      end
      
      # Final verification
      if user_config.exist?
        file_size = user_config.size
        ohai "✅ Final verification: Config file exists (#{file_size} bytes)"
      else
        onoe "❌ Final verification failed: Config file does not exist"
      end
      
    rescue => e
      onoe "💥 Error in post_install config setup: #{e.message}"
      ohai "🔍 Error class: #{e.class}"
      ohai "📍 Error backtrace: #{e.backtrace&.first}"
    end

    # Create version info file
    begin
      version_file = var / "lib" / "airconnect" / "VERSION"
      ohai "📝 Creating version file: #{version_file}"
      version_file.write version.to_s
      ohai "✅ Version file created: #{version}"
    rescue => e
      onoe "💥 Error creating version file: #{e.message}"
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
        Config file: ~/.config/airconnect/airconnect.conf
        Log files: #{var}/log/
      
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
        ~/.config/airconnect/airconnect.conf
      
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
end
