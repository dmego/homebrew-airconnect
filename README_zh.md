# 🎵 AirConnect Homebrew Tap

[AirConnect](https://github.com/philippe44/AirConnect) 的 Homebrew tap - 使用 AirPlay 将音频流传输到 UPnP/Sonos 和 Chromecast 设备。

[![Update AirConnect Version](https://github.com/dmego/homebrew-airconnect/actions/workflows/update-airconnect.yml/badge.svg)](https://github.com/dmego/homebrew-airconnect/actions/workflows/update-airconnect.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 功能特性

- 🔄 **自动更新**: 自动跟踪 AirConnect 最新版本
- 🛠️ **统一服务管理**: 使用单一命令控制 AirCast 和 AirUPnP
- 📊 **健康监控**: 服务故障时自动重启
- 📝 **详细日志**: 提供详细日志用于故障排除
- ⚙️ **可配置**: 简单的配置管理
- 🎯 **macOS 优化**: 原生 macOS 服务集成

## 📦 安装

### 快速安装

```bash
# 添加 tap
brew tap dmego/airconnect

# 安装 AirConnect（Formula - 推荐用于命令行使用）
brew install airconnect
```

### 启动服务

```bash
# 启动 AirConnect（同时启动 AirCast 和 AirUPnP）
brew services start airconnect

# 检查状态
airconnect status
```

## 🎮 使用方法

### 服务管理

```bash
# 启动服务
brew services start airconnect

# 停止服务
brew services stop airconnect

# 重启服务
brew services restart airconnect

# 检查所有 Homebrew 服务
brew services list
```

### AirConnect 管理工具

这个 tap 包含一个强大的管理工具，可通过 `airconnect` 命令访问：

```bash
# 显示详细状态
airconnect status

# 查看日志
airconnect logs                    # 所有日志
airconnect logs aircast           # 仅 AirCast
airconnect logs airupnp           # 仅 AirUPnP
airconnect logs service           # 仅服务管理器

# 实时跟踪日志
airconnect follow                 # 所有日志
airconnect follow aircast         # 仅 AirCast

# 配置管理
airconnect config                 # 编辑配置
airconnect config show            # 显示当前配置
airconnect config reset           # 重置为默认值

# 系统诊断
airconnect diagnostics            # 运行系统检查

# 版本和更新
airconnect version                # 显示版本信息
airconnect update-check           # 检查更新

# 帮助
airconnect help                   # 显示详细帮助
```

### 直接使用二进制文件

你也可以直接使用各个组件：

```bash
# 手动启动 AirCast（用于 Chromecast 设备）
aircast -d all=info

# 手动启动 AirUPnP（用于 UPnP/Sonos 设备）
airupnp -d all=info
```

## ⚙️ 配置

### 配置文件

AirConnect 使用由 Homebrew 管理的包装层配置文件，路径为 `$HOMEBREW_PREFIX/etc/airconnect/airconnect.conf`：

```bash
# 编辑配置
airconnect config

# 显示当前配置
airconnect config show
```

### 配置示例

```bash
# 服务参数
AIRCAST_ARGS="-Z -d all=info"
AIRUPNP_ARGS="-Z -d all=info"

# 共享网络接口覆盖
NETWORK_INTERFACE="en0"

# 单服务覆盖
AIRCAST_NETWORK_INTERFACE=""
AIRUPNP_NETWORK_INTERFACE=""

# 可选的上游 AirConnect XML 配置文件
AIRCAST_CONFIG_XML=""
AIRUPNP_CONFIG_XML=""

# 健康监控
HEALTH_CHECK_INTERVAL="30"
RESTART_DELAY="5"
MAX_RESTART_ATTEMPTS="3"

# 调试模式
DEBUG="0"

# 当服务日志超过该大小（MB）时轮转
LOG_MAX_SIZE_MB="10"
```

### 高级配置选项

| 选项 | 描述 | 默认值 |
|------|------|--------|
| `AIRCAST_ARGS` | AirCast 服务参数 | `-Z -d all=info` |
| `AIRUPNP_ARGS` | AirUPnP 服务参数 | `-Z -d all=info` |
| `NETWORK_INTERFACE` | 对两个服务生效的共享接口/IP 覆盖 | 空 |
| `AIRCAST_NETWORK_INTERFACE` | 仅对 AirCast 生效的接口/IP 覆盖 | 空 |
| `AIRUPNP_NETWORK_INTERFACE` | 仅对 AirUPnP 生效的接口/IP 覆盖 | 空 |
| `AIRCAST_CONFIG_XML` | 通过 `-x` 传递的可选 AirCast XML 配置 | 空 |
| `AIRUPNP_CONFIG_XML` | 通过 `-x` 传递的可选 AirUPnP XML 配置 | 空 |
| `HEALTH_CHECK_INTERVAL` | 健康检查频率（秒） | `30` |
| `RESTART_DELAY` | 重启前延迟（秒） | `5` |
| `MAX_RESTART_ATTEMPTS` | 最大重启尝试次数 | `3` |
| `DEBUG` | 启用调试日志 | `0` |
| `LOG_MAX_SIZE_MB` | 服务日志达到该大小（MB）后轮转 | `10` |

### 包装层配置与上游 XML 的区别

`airconnect config` 管理的是这个 tap 的包装层配置文件，用来控制 `aircast` 和 `airupnp` 的启动参数。

如果 AirConnect 日志里出现 `no config file, using defaults`，它说的是上游可选 XML 配置没有通过 `-x` 传入，并不表示 `$HOMEBREW_PREFIX/etc/airconnect/airconnect.conf` 没有生效。

如果你需要上游 XML 配置，可以先用 `-i` 生成参考文件，再通过 `AIRCAST_CONFIG_XML` / `AIRUPNP_CONFIG_XML` 让包装层把它作为 `-x` 传给上游程序：

```bash
aircast -i "$HOMEBREW_PREFIX/etc/airconnect/aircast.xml"
airupnp -i "$HOMEBREW_PREFIX/etc/airconnect/airupnp.xml"
```

然后在 `airconnect.conf` 中设置 `AIRCAST_CONFIG_XML` 和 `AIRUPNP_CONFIG_XML`。

## 📊 监控和日志

### 日志位置

| 服务 | 日志文件 |
|------|----------|
| 服务管理器 | `/opt/homebrew/var/log/airconnect-service.log` |
| AirCast | `/opt/homebrew/var/log/aircast.log` |
| AirUPnP | `/opt/homebrew/var/log/airupnp.log` |

### 查看日志

```bash
# 快速查看日志
airconnect logs

# 实时跟踪日志
airconnect follow

# 查看特定服务日志
airconnect logs aircast
airconnect logs airupnp
airconnect logs service

# 查看更多行数
airconnect logs all 100
```

### 服务状态

```bash
# 详细状态信息
airconnect status

# 快速 Homebrew 服务状态
brew services list | grep airconnect
```

## 🔄 更新

### 自动更新

这个 tap 自动跟踪上游 AirConnect 版本。

### 手动检查更新

```bash
# 检查更新
airconnect update-check

# 更新到最新版本
brew upgrade airconnect
```

### 更新流程

1. GitHub Actions 每天监控上游仓库
2. 检测到新版本时，自动创建 PR
3. PR 包含版本更新和验证
4. 审查并合并后，用户可以使用 `brew upgrade` 更新

## 🛠️ 故障排除

### 常见问题

#### 服务无法启动

```bash
# 检查系统诊断
airconnect diagnostics

# 检查服务日志
airconnect logs service

# 验证二进制文件是否正常
aircast --help
airupnp --help
```

#### 找不到设备

```bash
# 检查网络连接
ping 8.8.8.8

# 检查端口是否可用
airconnect diagnostics

# 尝试手动发现
aircast -d all=info -v
airupnp -d all=info -v
```

#### 权限问题

```bash
# 检查文件权限
airconnect diagnostics

# 重置配置
airconnect config reset

# 如需要可重新安装
brew uninstall airconnect
brew install airconnect
```

### 调试模式

启用调试模式以获得详细日志：

```bash
# 编辑配置并设置 DEBUG="1"
airconnect config

# 重启服务
brew services restart airconnect

# 查看调试日志
airconnect follow
```

### 获取帮助

1. **检查日志**: `airconnect logs`
2. **运行诊断**: `airconnect diagnostics`
3. **检查配置**: `airconnect config show`
4. **查看文档**: 本 README 和上游文档
5. **创建 issue**: [GitHub Issues](https://github.com/dmego/homebrew-airconnect/issues)

## 🗑️ 卸载

### 标准卸载

```bash
# 停止服务
brew services stop airconnect

# 卸载
brew uninstall airconnect

# 移除 tap（可选）
brew untap dmego/airconnect
```

## 🔧 开发

### 仓库结构

```txt
homebrew-airconnect/
├── .github/workflows/          # GitHub Actions 自动化工作流
│   └── update-airconnect.yml   # 自动版本更新和发布工作流
├── Formula/                    # Homebrew Formula 定义
│   └── airconnect.rb          # AirConnect Formula 主文件
├── scripts/                   # 辅助脚本集合
│   ├── airconnect-service.sh  # 后台服务启动和管理脚本
│   └── airconnect-manager.sh  # 命令行管理工具主脚本
├── configs/                   # 配置文件模板
│   └── airconnect.conf        # 默认配置文件模板
├── CHANGELOG.md               # 版本更新记录和发布说明
├── LICENSE                    # MIT 开源许可证
├── README.md                  # 英文项目文档
└── README_zh.md              # 中文项目文档
```

### 贡献指南

1. Fork 本仓库
2. 创建功能分支
3. 完成你的更改
4. 充分测试
5. 提交 Pull Request

### 测试方法

```bash
# 从本地 tap 安装
brew install --formula ./Formula/airconnect.rb

# 测试服务功能
brew services start airconnect
airconnect status
airconnect logs
```

## 📜 许可证

本项目采用 MIT 许可证 - 详情请查看 [LICENSE](../LICENSE) 文件。

## 🙏 致谢

- [philippe44](https://github.com/philippe44) - AirConnect 创建者
- [Homebrew](https://brew.sh/) - macOS 包管理器
- AirConnect 社区

## 📞 支持

- **问题反馈**: [GitHub Issues](https://github.com/dmego/homebrew-airconnect/issues)
- **讨论**: [GitHub Discussions](https://github.com/dmego/homebrew-airconnect/discussions)
- **上游项目**: [AirConnect 仓库](https://github.com/philippe44/AirConnect)
