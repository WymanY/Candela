# 开发 Candela

本地构建和调试。产品首页见 [README.md](../README.md)。English: [developing.en.md](developing.en.md)

## 克隆

仓库已经提交 `Candela.xcodeproj`，克隆后不必先装 XcodeGen。

```sh
git clone https://github.com/WymanY/Candela.git
cd Candela
open Candela.xcodeproj
```

选择 **Candela** scheme 后运行。这是店外直装 / Developer ID 构建。

- **Debug：** 同时显示 Dock 图标和菜单栏图标，方便找到应用。
- **Release：** 只显示菜单栏。

命令行：

```sh
xcodebuild -project Candela.xcodeproj -scheme Candela -configuration Debug -destination 'platform=macOS' build
swift test --package-path .
swift run --package-path . candela-cli --help
```

Debug 包通常在：

```
~/Library/Developer/Xcode/DerivedData/Candela-*/Build/Products/Debug/Candela.app
```

## Candela 和 CandelaMAS

**Candela** scheme 是直装版：关沙盒，走系统背光、DDC 和显示器控制。不要把这个 scheme 上传到 Mac App Store。

**CandelaMAS** 是可审核的沙盒构建线，不是一次完整上架。界面和功能面保持一样；私有显示 API 不会编进包，硬件控制改走公开接口。沙盒下的显示器 I/O 仍需真机验证，仓库也还没有 Mac App Store 签名和描述文件。

```sh
xcodebuild -project Candela.xcodeproj -scheme CandelaMAS -configuration Release -destination 'generic/platform=macOS' build
```

## 重新生成 Xcode 工程

只有改了 `project.yml` 才需要：

```sh
chmod +x Scripts/generate_project.sh
./Scripts/generate_project.sh
```

CI 会先跑 `xcodegen generate` 再构建，工程漂移会被抓出来。

## 假硬件

不想写真实显示器时，可以这样跑 UI：

```
# Scheme → Run → Arguments
--fake-hardware

# 或
CANDELA_FAKE_HARDWARE=1
```

假硬件目录是：

- Built-in — 系统背光亮度，没有音量和旋转
- DELL U2723QE — DDC 亮度 + 音量
- HDMI Television — 软件调光；匹配到 HDMI 音箱时有软件音量
- Sidecar — Unsupported / 不支持，灰色，没有滑条

## 命令行、MCP、socket

先让 Candela 保持运行。CLI 通过 `~/Library/Application Support/Candela/control.sock` 和控制面通信。

显示器查询可以用名称、自定义名、`main`、`builtin` 或 `external`。数值范围是 `0...1`。

```sh
swift run --package-path . candela-cli list
swift run --package-path . candela-cli get --display builtin
swift run --package-path . candela-cli set-brightness --display builtin --value 0.35
swift run --package-path . candela-cli preset night
swift run --package-path . candela-cli scenes
swift run --package-path . candela-cli save-scene --name Night
swift run --package-path . candela-cli apply-scene Night
```

`candela-mcp` 是本地 stdio MCP 服务，操作与 CLI 相同。Codex skill 在 [`skills/candela`](../skills/candela)。

## App Intents 日志

从 Xcode 启动时，控制台可能打印 `com.apple.linkd.autoShortcut` / `Error registering app with intents framework`。Candela 没有 App Intents，这条日志可以忽略。详见 [linkd-diagnosis.md](linkd-diagnosis.md)。
