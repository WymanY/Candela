# 使用 Candela

菜单栏应用的使用说明。产品首页见 [README.md](../README.md)。English: [using.en.md](using.en.md)

界面文案保留英文原文，中文翻译写在旁边。

## 显示器发现

插上或拔掉外接屏、合盖、热插拔后，菜单栏面板会自动更新。合盖睡眠的内建屏、镜像从屏会隐藏。

Sidecar、AirPlay、Continuity、DisplayLink 会显示为 Unsupported / 不支持：能看见，但不能控制。

## 亮度

苹果内建屏和苹果外接屏走系统背光。第三方 HDMI / DisplayPort / USB-C 显示器在 Apple Silicon 上走 DDC 亮度。硬件控制不可用或失败时，回退到 Software dimming / 软件调光。

面板顶部的 Night / 夜间、Desk / 桌面、Max / 最大 分别是 20%、50%、100%。Match All / 全部匹配 会把一块屏的亮度（以及可用的音量 / 对比度）同步到其他屏。

打开 Follow keyboard brightness / 跟随键盘亮度后，F1 / F2 仍只动内建屏，其他屏按相对偏移一起变化。这个开关只对本次启动有效；下次启动仍是关闭。拖某一块屏的滑条只会改它自己的偏移。Candela 不会接管媒体键。

设置里打开 Restore last brightness on reconnect / 重新连接时恢复上次亮度 后，显示器重新接入时会回到上次亮度。菜单栏滑条会跟上键盘、系统设置或显示器 OSD 改过的硬件亮度，不会把读到的值再写回去。

笔记本 / iMac 内建屏不显示音量行。外接屏有匹配的 HDMI / DisplayPort / Thunderbolt 音箱时，走系统音量；显示器提供 DDC 音量时走 DDC；数字输出没有硬件滑条时，回退到软件衰减。软件音量需要屏幕录制；HDMI / DP 软件音量还需要音频采集权限。

外接屏可旋转时，支持 0° / 90° / 180° / 270°。内建屏不提供旋转。显示器响应对应控制时，也可以改对比度和输入。

## Mirror / 镜像 和 Layout / 布局

面板底部的 Mirror / 镜像 会把每块外接屏镜像到内置屏；按钮变成 Unmirror / 取消镜像 后再点一次，按上次的排列恢复。镜像后外接行会暂时隐藏，按钮仍留在底部。只有一块真实屏时，Mirror / 镜像 会收起来。

Layout / 布局 打开独立窗口 Display Layout / 显示器排列，用来 Arrange extended displays / 排列扩展显示器。拖动任意显示器，停手后会自动应用。需要至少两块真实屏，并且当前不能处于镜像。窗口底部只有 Done。

Mirror / 镜像 是叠到内置屏；Layout / 布局 是改扩展桌面的相对位置。两者不要同时用。

## Picture in Picture / PiP 和 Display Overview / 多屏预览

每一块真实显示器都有 PiP 按钮。底部 Overview / 多屏 打开 Display Overview / 多屏预览。

PiP 是可拖动、可缩放的浮窗，默认落在鼠标所在的那块屏上。源可以是 Display / 显示器、Window / 窗口，或跟着光标走的 Magnifier / 放大镜。还没选窗口时，Window / 窗口 仍显示这块屏。Display / 显示器 和 Window / 窗口 提示 Scroll to zoom / 滚轮缩放；Magnifier / 放大镜 提示 Space-drag to pan / 按住空格拖动平移。预览可左右翻转，方便当提词器。

标题栏可调 Opacity / 不透明度（最低 25%），也能打开 Click Through / 点击穿透：点预览画面会点到下面的窗口，鼠标停在 PiP 上时滚轮仍缩放这个窗口。Pin Corner / 固定到角落 可以钉在左上 / 右上 / 左下 / 右下，或居中；拖离钉住的位置会自动取消。每块屏会记住上次的位置、大小、透明度和窗口状态。

Esc 关闭当前悬停的 PiP 或 Display Overview / 多屏预览；没有悬停时先关 Overview / 多屏，再关所有 PiP。Control-Esc 只退出源控制。鼠标停在窗口上时，⌘W 仍关闭这个窗口。

Display Overview / 多屏预览 把所有真实屏缩成一格。每格右上角可以叉掉不想看的屏；标题栏的 Show Hidden / 显示隐藏 会把它们重新打开。关掉整个监视墙，或把里面的格子全部叉掉，菜单栏 Overview / 多屏 都会一起退出。下次再开会重新显示全部。Sidecar 等虚拟屏不会进墙。

Picture in Picture / PiP 和 Display Overview / 多屏预览 需要「屏幕录制」权限：System Settings → Privacy & Security → Screen Recording。

## Scenes / 场景

菜单栏可 Save Scene / 保存场景，并一键 Apply Scene / 应用场景。应用时也会切回当时选中的扬声器，并还原它的音量和静音。这是 Candela 会改系统默认音频输出的唯一情况。

Settings / 设置 里的 Scenes / 场景 页可以重命名、更新或删除。同名保存会覆盖旧场景，不会另外复制一份。某块屏当前没接上时会跳过，接回来后再应用即可。应用不附带内置模板；保存的场景写进本机偏好设置，重启后还在。

## 电池

笔记本没插电源时，菜单栏面板标题右侧会显示当前电量和剩余使用时间。插上电源后改成充电图标。台式机或读不到内建电池时，这块提示会收起来。

## Settings / 设置

- Launch at Login / 登录时打开
- Restore last brightness on reconnect / 重新连接时恢复上次亮度
- Follow keyboard brightness / 跟随键盘亮度
- Software dimming / 软件调光
- Allow dim to black / 允许调到全黑
- Show percent next to sliders / 在滑块旁显示百分比
- 为每块屏设置自定义名称
- 保存和应用 Scenes / 场景

## 权限

- Picture in Picture / PiP、Display Overview / 多屏预览、软件音量：屏幕录制
- HDMI / DP 软件音量：音频采集
- 源控制（把点击和滚动送到另一块屏）：辅助功能；Control-Esc 退出
