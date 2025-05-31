cask "airconnect" do
  arch arm: "arm64", intel: "x86_64"

  # Use dynamic version fetching to always get the latest
  version :latest
  sha256 :no_check

  url do
    require "open-uri"
    require "json"
    
    begin
      # Get latest release info from GitHub API
      api_url = "https://api.github.com/repos/philippe44/AirConnect/releases/latest"
      response = JSON.parse(URI.open(api_url, "User-Agent" => "Homebrew").read)
      latest_version = response["tag_name"]
      
      "https://github.com/philippe44/AirConnect/releases/download/#{latest_version}/AirConnect-#{latest_version}.zip"
    rescue => e
      # Fallback to a known working version if API fails
      opoo "Failed to fetch latest version (#{e.message}), using fallback"
      "https://github.com/philippe44/AirConnect/releases/download/1.8.3/AirConnect-1.8.3.zip"
    end
  end

  name "AirConnect"
  desc "Use AirPlay to stream to UPnP/Sonos & Chromecast devices"
  homepage "https://github.com/philippe44/AirConnect"

  # This will check for updates automatically
  livecheck do
    url :homepage
    strategy :github_latest
  end

  # Install individual binaries for direct access
  binary "aircast-macos-#{arch}-static", target: "aircast"
  binary "airupnp-macos-#{arch}-static", target: "airupnp"

  # Download and prepare support scripts
  preflight do
    # Get current version for scripts
    require "open-uri"
    require "json"
    
    current_version = "latest"
    begin
      api_url = "https://api.github.com/repos/philippe44/AirConnect/releases/latest"
      response = JSON.parse(URI.open(api_url, "User-Agent" => "Homebrew").read)
      current_version = response["tag_name"]
      ohai "Installing AirConnect version: #{current_version}"
    rescue => e
      opoo "Could not fetch version info: #{e.message}"
    end
    
    # Store version info for scripts
    version_file = staged_path/"VERSION"
    version_file.write(current_version)
    
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
        create_fallback_files(support_dir, target)
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
    
    if (staged_path/"VERSION").exist?
      system_command "cp", args: [staged_path/"VERSION", version_dir/"VERSION"]
    end
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
    # Get installed version for display
    version_file = Pathname("#{HOMEBREW_PREFIX}/var/lib/airconnect/VERSION")
    installed_version = version_file.exist? ? version_file.read.strip : "latest"
    
    puts <<~EOS
      
      🎉 AirConnect has been successfully installed!
      
      INSTALLED VERSION: #{installed_version}
      
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
        https://github.com/dmego/homebrew-airconnect
      
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

  private

  # Create minimal fallback files if download fails
  def create_fallback_files(support_dir, filename)
    case filename
    when "airconnect-service.sh"
      (support_dir/filename).write(<<~SCRIPT)
        #!/bin/bash
        echo "Minimal fallback service script"
        echo "Please update from: https://github.com/dmego/homebrew-airconnect"
        exec "${HOMEBREW_PREFIX:-/opt/homebrew}/bin/aircast" -d all &
        exec "${HOMEBREW_PREFIX:-/opt/homebrew}/bin/airupnp" -d all &
        wait
      SCRIPT
    when "airconnect-manager.sh"
      (support_dir/filename).write(<<~SCRIPT)
        #!/bin/bash
        echo "Minimal fallback management script"
        echo "Please update from: https://github.com/dmego/homebrew-airconnect"
        echo "Use 'brew services' commands to manage AirConnect"
      SCRIPT
    when "airconnect.conf"
      (support_dir/filename).write(<<~CONFIG)
        # AirConnect Configuration - Fallback Version
        # Please update from: https://github.com/dmego/homebrew-airconnect
        AIRCAST_ARGS="-d all -l 1000"
        AIRUPNP_ARGS="-d all -l 1000"
      CONFIG
    end
  end
end