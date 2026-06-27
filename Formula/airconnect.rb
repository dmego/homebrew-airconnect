require "fileutils"

class Airconnect < Formula
  desc "Use AirPlay to stream to UPnP/Sonos & Chromecast devices"
  homepage "https://github.com/philippe44/AirConnect"
  url "https://github.com/philippe44/AirConnect/releases/download/1.9.3/AirConnect-1.9.3.zip"
  sha256 "9ad2bf7397e1c7617c3112dd4c450b5f403a62470ad9e9e6a04db1b0f2f6db73"
  license "MIT"
  depends_on :macos

  resource "airconnect-support" do
    url "https://github.com/dmego/homebrew-airconnect/releases/download/airconnect-support-1.9.3/homebrew-airconnect-support-1.9.3.tar.gz"
    sha256 "127d5aa9816522790d500f10d338d8dcfc8d9f62c86fc9dcb7df719997f2bc33"
  end

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

    resource("airconnect-support").stage do
      bin.install "scripts/airconnect-service.sh" => "airconnect-service"
      bin.install "scripts/airconnect-manager.sh" => "airconnect"
      (var/"lib/airconnect").install "configs/airconnect.conf" => "airconnect.conf.default"
    end

    chmod 0755, bin/"airconnect-service"
    chmod 0755, bin/"airconnect"

    # Remove quarantine attributes to prevent Gatekeeper issues
    [
      bin/"aircast",
      bin/"airupnp",
      bin/"airconnect-service"
    ].each do |binary|
      next unless binary.exist?

      quiet_system "xattr", "-d", "com.apple.quarantine", binary.to_s
    end
  end

  def uninstall
    ohai "Uninstalling AirConnect..."
    
    # Stop the service using launchctl directly since brew command might not be available
    plist_path = "#{ENV["HOME"]}/Library/LaunchAgents/homebrew.mxcl.airconnect.plist"
    if File.exist?(plist_path)
      ohai "Stopping service via launchctl..."
      system "launchctl", "unload", plist_path
    end
    
    # Also try to stop processes directly
    ohai "Stopping any running AirConnect processes..."
    ["airconnect-service", "aircast", "airupnp"].each do |name|
      system "pkill", "-f", "#{homebrew_prefix}/bin/#{name}"
    end

    [
      var/"run/aircast.pid",
      var/"run/airupnp.pid",
      var/"run/airconnect.pid",
      var/"run/airconnect-service.pid",
    ].each do |path|
      FileUtils.rm_f(path)
    end
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
      
      unless config_file.exist?
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
            AIRCAST_BIN="${HOMEBREW_PREFIX}/bin/aircast"
            AIRUPNP_BIN="${HOMEBREW_PREFIX}/bin/airupnp"
            
            # Log and PID directories
            LOG_DIR="${HOMEBREW_PREFIX}/var/log"
            PID_DIR="${HOMEBREW_PREFIX}/var/run"
            
            # Service arguments
            # Include -Z because the service runs these processes in the background.
            AIRCAST_ARGS="-Z -d all=info"
            AIRUPNP_ARGS="-Z -d all=info"

            # Shared network interface override for both services.
            # Example: NETWORK_INTERFACE="en0"
            NETWORK_INTERFACE=""

            # Service-specific overrides take precedence over NETWORK_INTERFACE.
            AIRCAST_NETWORK_INTERFACE=""
            AIRUPNP_NETWORK_INTERFACE=""

            # Optional upstream AirConnect XML config files.
            AIRCAST_CONFIG_XML=""
            AIRUPNP_CONFIG_XML=""
            
            # Health monitoring
            HEALTH_CHECK_INTERVAL="30"  # seconds between health checks
            RESTART_DELAY="5"           # seconds to wait before restart
            MAX_RESTART_ATTEMPTS="3"    # max restart attempts before giving up
            
            # Debug mode (1 to enable, 0 to disable)
            DEBUG="0"

            # Rotate service logs when they exceed this size in MB.
            LOG_MAX_SIZE_MB="10"
            
            # Custom device exclusions (comma-separated)
            # EXCLUDED_DEVICES="device1,device2"
          CONFIG
        end
      else
        ohai "Preserving existing configuration at #{config_file}"
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
    environment_variables PATH: std_service_path_env, HOMEBREW_PREFIX: HOMEBREW_PREFIX.to_s
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
      if Dir.exist?(path)
        ohai "Removing directory: #{path}"
        FileUtils.rm_rf(path)
      elsif File.exist?(path)
        ohai "Removing file: #{path}"
        FileUtils.rm_f(path)
      end
    end
    
    # Clean up any remaining processes
    ohai "Stopping any remaining AirConnect processes..."
    ["airconnect-service", "aircast", "airupnp"].each do |name|
      system "pkill", "-f", "#{homebrew_prefix}/bin/#{name}"
    end
    
    # Clean up glob patterns
    glob_patterns = [
      "#{homebrew_prefix}/var/log/air*.log",
      "#{homebrew_prefix}/var/run/air*.pid",
      "/tmp/airconnect*",
      "/var/log/airconnect*"
    ]
    
    glob_patterns.each do |pattern|
      Dir.glob(pattern).each do |path|
        next if path == "." || path == ".."

        if Dir.exist?(path)
          ohai "Removing directory: #{path}"
          FileUtils.rm_rf(path)
        elsif File.exist?(path)
          ohai "Removing file: #{path}"
          FileUtils.rm_f(path)
        end
      end
    end
    
    ohai "Complete AirConnect cleanup finished!"
  end

  private

  def homebrew_prefix
    ENV["HOMEBREW_PREFIX"] || HOMEBREW_PREFIX
  end
end
