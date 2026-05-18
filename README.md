<h1 align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Logo" width="128">
  <br>Ghostty for Windows
</h1>

<p align="center">
  <b>Ghostty 终端模拟器的 Windows 原生移植版</b>
  <br>
  基于 Win32 API + Direct2D/D3D11 的高性能原生终端
  <br><br>
  <a href="#build">构建指南</a>
  ·
  <a href="#status">当前状态</a>
  ·
  <a href="#features">功能特性</a>
  ·
  <a href="#contributing">贡献指南</a>
</p>

---

## 简介

本项目是 [Ghostty](https://ghostty.org/) 终端模拟器的 **Windows 原生移植版**。Ghostty 以"快速、功能丰富、原生体验"著称，但官方目前仅支持 macOS 和 Linux。本项目填补了 Windows 平台的空白，让 Windows 用户也能体验到 Ghostty 的强大功能。

与 WSL 中运行 Linux 版 Ghostty 不同，这是一个**真正的原生 Windows 应用**：
- 基于 Win32 API 构建，不是 GTK/Qt/Electron
- 使用 Direct2D / D3D11 硬件加速渲染
- 集成 Windows ConPTY 作为终端后端
- 支持 Windows 原生输入法、AltGr、Emoji 等

## 当前状态

| 功能 | 状态 |
|------|:----:|
| 终端模拟（VT 序列、ConPTY） | ✅ |
| 多标签页（Tabs） | ✅ |
| 分屏（Split Panes） | ✅ |
| Direct2D 硬件加速渲染 | ✅ |
| D3D11 硬件加速渲染 | ✅ |
| DirectWrite 字体 + HarfBuzz 字形 | ✅ |
| Emoji / CJK / 字体回退链 | ✅ |
| 自定义标题栏（Custom Chrome） | ✅ |
| Acrylic / Mica 背景模糊 | ✅ |
| 搜索面板（Search Panel） | ✅ |
| 命令面板（Command Palette） | ✅ |
| 深色/浅色模式 | ✅ |
| 配置系统（ghostty config） | ✅ |
| 安装程序 / 自动更新 | ❌ |

> ⚠️ **注意**：项目仍在活跃开发中，部分功能可能不够稳定。欢迎提交 Issue 和 PR。

## 功能特性

### 原生 Win32 体验
- 真正的 Win32 窗口系统，不是跨平台 GUI 框架的妥协
- 自定义标题栏支持最大化/最小化/关闭，拖动从最大化状态恢复
- 支持 Windows 11 的 Acrylic 和 Mica 背景效果
- 沉浸式深色模式（DWMWA_USE_IMMERSIVE_DARK_MODE）

### 高性能渲染
- **Direct2D 渲染器**：稳定、兼容性好，适合日常使用
- **D3D11 渲染器**：更低延迟，支持更复杂的视觉效果
- 字体渲染使用 DirectWrite + HarfBuzz，支持连字（ligatures）
- 完整的字体回退链：英文字体 → CJK 字体 → Segoe UI Emoji

### 完整的终端功能
- Kitty 图形协议、图片协议
- 同步渲染、剪贴板序列
- 亮色/暗色模式通知
- 可配置的颜色主题（兼容 iTerm2 主题格式）

## 构建指南

### 前置要求

- **Zig** `0.15.2` 或更高版本（[下载地址](https://ziglang.org/download/)）
- **Windows 10/11**（64位）
- **Git**

### 快速构建

```powershell
# 克隆仓库
git clone https://github.com/zcg/ghostty-win.git
cd ghostty-win

# 构建（推荐命令）
zig build -Dapp-runtime=win32 -Doptimize=ReleaseSmall
```

构建完成后，可执行文件位于 `zig-out/bin/ghostty.exe`。

### 运行

```powershell
.\zig-out\bin\ghostty.exe
```

首次运行会自动创建默认配置文件在 `%LOCALAPPDATA%\ghostty\config`。

### 配置示例

```
# 字体设置
font-family = "JetBrainsMono Nerd Font", "Microsoft YaHei"
font-size = 12

# 主题
theme = "Catppuccin Mocha"

# 背景模糊（Windows 11）
background-blur = acrylic

# 窗口设置
window-padding-x = 4
window-padding-y = 4
```

## 项目结构

```
src/
├── apprt/win32/          # Win32 应用运行时
│   ├── App.zig           # 应用主循环
│   ├── Window.zig        # 窗口管理
│   ├── Surface.zig       # 终端表面
│   ├── d2d.zig           # Direct2D 渲染器
│   └── ...
├── renderer/
│   ├── Direct2D.zig      # D2D 渲染实现
│   └── D3D11.zig         # D3D11 渲染实现
├── font/
│   └── directwrite.zig   # DirectWrite 字体后端
└── ...
```

## 分支说明

| 分支 | 说明 |
|------|------|
| `ghostty_win_v2` | **主分支**，Direct2D 渲染器，当前最稳定 |
| `ghostty_win` | 早期版本，已归档 |
| `directx-renderer` | D3D11 渲染器实验分支 |
| `freetype-emoji` | Emoji 渲染优化实验 |
| `win32-apprt` | Win32 应用运行时原型 |

## 贡献指南

欢迎所有形式的贡献！无论是 Bug 报告、功能建议、代码提交还是文档改进。

### 提交 Issue

- 使用 [GitHub Issues](https://github.com/zcg/ghostty-win/issues)
- 请描述清楚问题现象、复现步骤、系统版本
- 如果是渲染问题，请提供截图和显卡信息

### 提交 PR

1. Fork 本仓库
2. 从 `ghostty_win_v2` 创建你的功能分支：`git checkout -b feature/xxx`
3. 提交更改（commit message 用英文，格式参考现有提交）
4. 推送到你的 Fork：`git push origin feature/xxx`
5. 在 GitHub 上发起 Pull Request

### 开发注意事项

- 本项目使用 **Zig** 编写，不是 C/C++/Rust
- Win32 相关的代码在 `src/apprt/win32/` 目录
- 渲染器代码在 `src/renderer/` 目录
- 提交信息格式：`win32: 简短描述`
- 请确保 `zig build` 能通过再提交

### 为什么不用 zigwin32 绑定库？

本项目的手写 Win32 API 声明全部集中在 `src/apprt/win32/sys.zig` 中，没有引入 [marlersoft/zigwin32](https://github.com/marlersoft/zigwin32) 这类外部绑定库。原因如下：

1. **精简依赖**：只声明实际用到的类型和函数，避免拉入整个 Win32 API 绑定，减少构建时间和依赖复杂度。
2. **新 API 支持**：Windows 11 的 DWM  backdrop 效果（Acrylic/Mica）、ConPTY 等新 API 在 zigwin32 中更新滞后，手写声明可以第一时间使用系统新特性。
3. **灵活定制**：部分 API 需要根据项目场景做适配（如 `WNDPROC` 的调用约定、`AccentPolicy` 的字段布局），手写比绑定库生成的代码更可控。
4. **Zig 演进兼容**：`std.os.windows` 模块在不同 Zig 版本间有符号删减风险，集中管理自己的声明比依赖外部绑定库更容易维护。

## 致谢

- [Mitchell Hashimoto](https://github.com/mitchellh) 和 [Ghostty 团队](https://github.com/ghostty-org) — 创造了如此优秀的终端模拟器
- [Yasuhiro Matsumoto (mattn)](https://github.com/mattn) — 最初的 Win32 移植工作
- 所有为本项目做出贡献的开发者

## 许可证

本项目基于 [MIT 许可证](LICENSE) 开源。

Ghostty 原始代码版权归属 Mitchell Hashimoto 和 Ghostty 贡献者。Windows 移植部分的修改和新增代码遵循同样的 MIT 许可证。
