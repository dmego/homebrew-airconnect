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
            echo "Minimal fallback service script"
            echo "Please update from: https://github.com/dmego/homebrew-airconnect"
            exec "${HOMEBREW_PREFIX:-/opt/homebrew}/bin/aircast" -d all &
            exec "${HOMEBREW_PREFIX:-/opt/homebrew}/bin/airupnp" -d all &
            wait
          SCRIPT
        when "airconnect-manager.sh"
          (support_dir/target).write(<<~SCRIPT)
            #!/bin/bash
            echo "Minimal fallback management script"
            echo "Please update from: https://github.com/dmego/homebrew-airconnect"
            echo "Use 'brew services' commands to manage AirConnect"
          SCRIPT
        when "airconnect.conf"
          (support_dir/target).write(<<~CONFIG)
            # AirConnect Configuration - Fallback Version
            # Please update from: https://github.com/dmego/homebrew-airconnect
            AIRCAST_ARGS="-d all -l 1000"
            AIRUPNP_ARGS="-d all -l 1000"
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

  # Service configuration
  service do
    name "homebrew.mxcl.airconnect"
    run [opt_bin/"airconnect-service"]
    keep_alive true
    log_path var/"log/airconnect-service.log"
    error_log_path var/"log/airconnect-service.log"
    working_dir var
    process_type :background
  end

  # Post-installation message
  postflight do
    puts <<~EOS
      
      🎉 AirConnect has been successfully installed!
      
      INSTALLED VERSION: #{version}
      
      QUICK START:
        brew services start airconnect    # Start the service
        airconnect status                # Check service status
        airconnect logs                  # View logs
        airconnect config                # Edit configuration
      
      FEATURES:
        ✅ Automatic service management and health monitoring
        ✅ Detailed logging for troubleshooting
        ✅ Unified control of both AirCast and AirUPnP
        ✅ Graceful shutdown and restart capabilities
        ✅ Auto-update support with version tracking
      
      MANAGEMENT:
        Use 'airconnect help' for detailed usage information
        Config file: ~/.config/airconnect/airconnect.conf
        Log files: #{var}/log/
      
      SERVICES:
        🎵 AirCast  - Streams to Chromecast devices
        🔊 AirUPnP  - Streams to UPnP/Sonos devices
      
      UPDATE CHECKING:
        airconnect update-check          # Check for updates
        brew upgrade --cask airconnect   # Update to latest version
      
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
    "#{var}/log/aircast.log",
    "#{var}/log/airupnp.log", 
    "#{var}/log/airconnect-service.log",
    "#{var}/run/aircast.pid",
    "#{var}/run/airupnp.pid",
    "#{var}/run/airconnect.pid",
  ]
end