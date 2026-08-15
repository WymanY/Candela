# Candela

Candela 是一款原生 macOS 菜单栏应用，用来控制本机接上的每一块显示器。它可以调节苹果屏和第三方显示器的亮度，在显示器带 HDMI/DP 音箱时调节音量，旋转外接屏，切换 DDC 输入，并把指定屏幕镜像到浮动画中画窗口。

这是一个 AppKit 菜单栏应用。Bundle ID：`app.candela.macos`。

English: [README.en.md](README.en.md)

## 功能

### 显示器发现

- 内建屏和外接屏插拔、合盖、热插拔后都会自动更新列表。
- 用稳定的 `persistentKey` 识别每一块屏，不依赖会话里的 `CGDirectDisplayID`。
- 合盖睡眠的内建屏、镜像从屏会隐藏。
- Sidecar、AirPlay、Continuity、DisplayLink 会显示为不支持：能看见，但不能控制。

### 亮度

- 苹果内建屏和苹果外接屏走 DisplayServices。
- 第三方 HDMI / DisplayPort / USB-C 显示器在 Apple Silicon 上走 DDC/CI VCP `0x10`。
- 硬件控制不可用或失败时，回退到软件 gamma 调光，并保持 LUT，避免被 WindowServer 冲掉。
- Night / Desk / Max 预设：20%、50%、100%。
- Match All 会把一块屏的亮度（以及可用的音量/对比度）同步到其他屏。
- 显示器重新接入时，可以恢复上次亮度。

### 音量

- 有匹配的 HDMI / DisplayPort / Thunderbolt 音箱时，走 Core Audio。
- 显示器提供对应 VCP 时，走 DDC 音量/静音。
- 数字输出没有硬件滑条时，回退到软件衰减。
- 笔记本 / iMac 内建屏不显示音量行。

### 其他显示器控制

- 显示器响应对应 VCP 时，支持 DDC 对比度（`0x12`）和输入切换（`0x60`）。
- 外接屏可旋转时，支持 0° / 90° / 180° / 270°。
- 内建屏不提供旋转。

### 画中画

- 菜单栏里每一块真实显示器都有 PiP 按钮。
- 打开后会在另一块屏上出现可拖动、可缩放的镜像窗口。滚轮或触控板捏合可放大缩小。
- 可调透明度，也能打开点击穿透，方便盯着看又不挡住下面的操作。
- 可钉在四个角落；关掉后再开会回到上次的位置、大小和透明度。
- 按源屏像素采集，文字更清楚。
- 需要「屏幕录制」权限。
- Sidecar 等虚拟屏不支持。

### 设置

- 登录时启动
- 重新接入时恢复上次亮度
- 开关软件调光
- 允许调到全黑
- 滑条旁显示百分比
- 为每块屏设置自定义名称

### 命令行 / Agent

先让 Candela 保持运行。CLI 通过 `~/Library/Application Support/Candela/control.sock` 和控制面通信。

```sh
swift run --package-path . candela-cli list
swift run --package-path . candela-cli get --display builtin
swift run --package-path . candela-cli set-brightness --display builtin --value 0.35
swift run --package-path . candela-cli set-volume --display DELL --value 0.2
swift run --package-path . candela-cli set-mute --display DELL --muted true
swift run --package-path . candela-cli set-contrast --display DELL --value 0.5
swift run --package-path . candela-cli set-input --display DELL hdmi1
swift run --package-path . candela-cli set-rotation --display DELL 90
swift run --package-path . candela-cli set-pip --display DELL --enabled true
swift run --package-path . candela-cli rename --display DELL --name Desk
swift run --package-path . candela-cli preset night
swift run --package-path . candela-cli match-all --display main
swift run --package-path . candela-cli dump
```

显示器查询可以用名称、自定义名、`persistentKey`、`main`、`builtin` 或 `external`。数值范围是 `0...1`。

`candela-mcp` 是本地 stdio MCP 服务，操作与 CLI 相同。Codex skill 在 `skills/candela`。

## 明确不做的事

Candela 不会创建虚拟屏、改写 EDID、解锁 XDR 亮度、强制 HiDPI 或自定义分辨率、接管媒体键，也不会改系统默认音频输出。

## 最低要求

| 项目 | 最低版本 |
| --- | --- |
| macOS | 14.0 Sonoma |
| Xcode | 16.0 |
| Swift | 5.10 语言模式（Swift 6.0 工具链） |
| 芯片 | Apple Silicon 或 Intel，必须原生运行，拒绝 Rosetta |
| XcodeGen | 2.42.0 或更新，仅在重新生成 Xcode 工程时需要 |

第三方显示器的 DDC 亮度/音量目前做在 Apple Silicon 上。画中画和软件音量需要屏幕录制权限。HDMI/DP 软件音量还需要音频采集权限。

## 构建

仓库里已经提交了生成好的 `Candela.xcodeproj`，克隆后不必先装 XcodeGen。

### 用 Xcode

```sh
git clone https://github.com/WymanY/Candela.git
cd Candela
open Candela.xcodeproj
```

选择 **Candela** scheme 后运行。

- **Debug：** 同时显示 Dock 图标和菜单栏图标，方便找到应用。
- **Release：** 只显示菜单栏。

启动时 Xcode 可能打印 `com.apple.linkd.autoShortcut` / `Error registering app with intents framework`。Candela 没有 App Intents，这条日志可以忽略。详见 `docs/linkd-diagnosis.md`。

### 命令行

```sh
# 应用
xcodebuild -project Candela.xcodeproj -scheme Candela -configuration Debug -destination 'platform=macOS' build

# 包测试、CLI、MCP
swift test --package-path .
swift run --package-path . candela-cli --help
```

Debug 包会生成在 DerivedData。本机 Xcode 构建后通常在：

```
~/Library/Developer/Xcode/DerivedData/Candela-*/Build/Products/Debug/Candela.app
```

### 重新生成 Xcode 工程

只有改了 `project.yml` 才需要：

```sh
chmod +x Scripts/generate_project.sh
./Scripts/generate_project.sh
```

CI 会先跑 `xcodegen generate` 再构建，工程漂移会被抓出来。

### 假硬件

不想写真实显示器时，可以这样跑 UI：

```
# Scheme → Run → Arguments
--fake-hardware

# 或
CANDELA_FAKE_HARDWARE=1
```

假硬件目录是：

- Built-in — DisplayServices 亮度，没有音量和旋转
- DELL U2723QE — DDC 亮度 + 音量
- HDMI Television — 软件 gamma；匹配到 HDMI 音箱时有软件音量
- Sidecar — 不支持，灰色，没有滑条

## 测试

```sh
swift test --package-path .
```

CI 还会在 macOS 14 上构建 Candela 应用。

## 许可证

MIT。见 `LICENSE` 和 `NOTICE`。
