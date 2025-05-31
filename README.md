# 🎵 AirConnect Homebrew Tap

A Homebrew tap for [AirConnect](https://github.com/philippe44/AirConnect) - Use AirPlay to stream to UPnP/Sonos & Chromecast devices.

[![Update AirConnect Version](https://github.com/dmego/homebrew-airconnect/actions/workflows/update-airconnect.yml/badge.svg)](https://github.com/dmego/homebrew-airconnect/actions/workflows/update-airconnect.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 Features

- 🔄 **Auto-updating**: Automatically tracks the latest AirConnect releases
- 🛠️ **Unified Service Management**: Control both AirCast and AirUPnP with a single command
- 📊 **Health Monitoring**: Automatic service restart on failure
- 📝 **Comprehensive Logging**: Detailed logs for troubleshooting
- ⚙️ **Configurable**: Easy configuration management
- 🎯 **macOS Optimized**: Native macOS service integration

## 📦 Installation

### Quick Install

```bash
# Add the tap
brew tap dmego/airconnect

# Install AirConnect (Formula - recommended for command line usage)
brew install airconnect
```

### Start the Service

```bash
# Start AirConnect (both AirCast and AirUPnP)
brew services start airconnect

# Check status
airconnect status
```

## 🎮 Usage

### Service Management

```bash
# Start services
brew services start airconnect

# Stop services  
brew services stop airconnect

# Restart services
brew services restart airconnect

# Check all Homebrew services
brew services list
```

### AirConnect Management Tool

The tap includes a powerful management tool accessible via the `airconnect` command:

```bash
# Show comprehensive status
airconnect status

# View logs
airconnect logs                    # All logs
airconnect logs aircast           # AirCast only
airconnect logs airupnp           # AirUPnP only
airconnect logs service           # Service manager only

# Follow logs in real-time
airconnect follow                 # All logs
airconnect follow aircast         # AirCast only

# Configuration management
airconnect config                 # Edit configuration
airconnect config show            # Show current config
airconnect config reset           # Reset to defaults

# System diagnostics
airconnect diagnostics            # Run system checks

# Version and updates
airconnect version                # Show version info
airconnect update-check           # Check for updates

# Help
airconnect help                   # Show detailed help
```

### Direct Binary Access

You can also use the individual components directly:

```bash
# Start AirCast manually (for Chromecast devices)
aircast -d all=info

# Start AirUPnP manually (for UPnP/Sonos devices)  
airupnp -d all=info
```

## ⚙️ Configuration

### Configuration File

AirConnect uses a configuration file located at `~/.config/airconnect/airconnect.conf`:

```bash
# Edit configuration
airconnect config

# Show current configuration
airconnect config show
```

### Example Configuration

```bash
# Service arguments
AIRCAST_ARGS="-d all=info"
AIRUPNP_ARGS="-d all=info"

# Health monitoring
HEALTH_CHECK_INTERVAL="30"
RESTART_DELAY="5"
MAX_RESTART_ATTEMPTS="3"

# Debug mode
DEBUG="0"
```

### Advanced Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `AIRCAST_ARGS` | Arguments for AirCast service | `-d all=info` |
| `AIRUPNP_ARGS` | Arguments for AirUPnP service | `-d all=info` |
| `HEALTH_CHECK_INTERVAL` | Health check frequency (seconds) | `30` |
| `RESTART_DELAY` | Delay before restart (seconds) | `5` |
| `MAX_RESTART_ATTEMPTS` | Max restart attempts | `3` |
| `DEBUG` | Enable debug logging | `0` |

## 📊 Monitoring and Logs

### Log Locations

| Service | Log File |
|---------|----------|
| Service Manager | `/opt/homebrew/var/log/airconnect-service.log` |
| AirCast | `/opt/homebrew/var/log/aircast.log` |
| AirUPnP | `/opt/homebrew/var/log/airupnp.log` |

### Viewing Logs

```bash
# Quick log view
airconnect logs

# Follow logs in real-time
airconnect follow

# View specific service logs
airconnect logs aircast
airconnect logs airupnp
airconnect logs service

# View more lines
airconnect logs all 100
```

### Service Status

```bash
# Detailed status information
airconnect status

# Quick Homebrew service status
brew services list | grep airconnect
```

## 🔄 Updates

### Automatic Updates

This tap automatically tracks upstream AirConnect releases. The cask always installs the latest version.

### Manual Update Check

```bash
# Check for updates
airconnect update-check

# Update to latest version
brew upgrade --cask airconnect
```

### Update Process

1. GitHub Actions monitors the upstream repository daily
2. When a new release is detected, an automatic PR is created
3. The PR includes version updates and verification
4. After review and merge, users can update with `brew upgrade`

## 🛠️ Troubleshooting

### Common Issues

#### Services Won't Start

```bash
# Check system diagnostics
airconnect diagnostics

# Check service logs
airconnect logs service

# Verify binaries are working
aircast --help
airupnp --help
```

#### No Devices Found

```bash
# Check network connectivity
ping 8.8.8.8

# Check if ports are available
airconnect diagnostics

# Try manual discovery
aircast -d all=info -v
airupnp -d all=info -v
```

#### Permission Issues

```bash
# Check file permissions
airconnect diagnostics

# Reset configuration
airconnect config reset

# Reinstall if needed
brew uninstall --cask airconnect
brew install --cask airconnect
```

### Debug Mode

Enable debug mode for detailed logging:

```bash
# Edit config and set DEBUG="1"
airconnect config

# Restart services
brew services restart airconnect

# Check debug logs
airconnect follow
```

### Getting Help

1. **Check logs**: `airconnect logs`
2. **Run diagnostics**: `airconnect diagnostics`
3. **Check configuration**: `airconnect config show`
4. **Review documentation**: This README and upstream docs
5. **Create an issue**: [GitHub Issues](https://github.com/dmego/homebrew-airconnect/issues)

## 🗑️ Uninstallation

### Standard Uninstall

```bash
# Stop services
brew services stop airconnect

# Uninstall cask
brew uninstall --cask airconnect

# Remove tap (optional)
brew untap dmego/airconnect
```

### Complete Cleanup

```bash
# Stop and uninstall
brew services stop airconnect
brew uninstall --cask airconnect

# Remove all data and logs
brew uninstall --zap --cask airconnect

# Remove tap
brew untap dmego/airconnect
```

## 🔧 Development

### Repository Structure

```txt
homebrew-airconnect/
├── .github/workflows/          # GitHub Actions
├── Casks/airconnect.rb        # Main cask definition
├── scripts/                   # Service and management scripts
└── configs/                   # Configuration templates
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Testing

```bash
# Install from local tap
brew install --cask ./Casks/airconnect.rb

# Test service functionality
brew services start airconnect
airconnect status
airconnect logs
```

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🙏 Acknowledgments

- [philippe44](https://github.com/philippe44) - Creator of AirConnect
- [Homebrew](https://brew.sh/) - Package manager for macOS
- The AirConnect community

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/dmego/homebrew-airconnect/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dmego/homebrew-airconnect/discussions)
- **Upstream**: [AirConnect Repository](https://github.com/philippe44/AirConnect)
