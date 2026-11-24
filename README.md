# Omni Player · 全平台播放器

Flutter + Dart + media_kit 实现的跨平台播放器 MVP。无需登录、不上传本地媒体、无内置遥测。网络视频仅由播放引擎向所选媒体地址发出请求。

## 功能
- 多选本地视频、音频，或添加 HTTP(S) 网络媒体
- 自适应布局（宽屏双栏、小屏上下排列）与深色主题
- 播放/暂停、进度拖动、全屏（由 media_kit 默认控件提供）
- 播放列表、跳转、移除、清空、快进/快退、倍速、循环、静音
- 错误提示与加载反馈
- URL 校验单元测试、GitHub Actions 检查和 Web 构建

## 快速开始
安装 Flutter stable（建议 Flutter 3.38 或更新版本）、Python 3、对应平台 SDK。该源码包采用按需生成官方平台 runner 的方式，首次启动必须运行：

```sh
python scripts/bootstrap.py
flutter analyze
flutter test
flutter run -d chrome
```

Linux 需安装 Flutter 桌面构建依赖以及 libmpv（Ubuntu 示例：`sudo apt install libmpv-dev mpv`）。Windows 需 Visual Studio C++ 桌面工作负载；Android 需 Android SDK；macOS/iOS 需 Xcode 与 CocoaPods。若某个目标的平台工具链未安装，按 Flutter doctor 的提示配置。首次生成后建议将平台目录和 pubspec.lock 提交。

| 平台 | 运行/打包 |
|---|---|
| Windows | `flutter build windows`（Windows 主机） |
| macOS | `flutter build macos`（Mac） |
| Linux | `flutter build linux`（Linux） |
| Android | `flutter build apk --split-per-abi` |
| iOS | `flutter build ios --no-codesign`（Mac；发布需要签名） |
| Web | `flutter build web --release` |

## 格式与限制
原生平台使用 media_kit 的原生播放引擎，支持能力取决于所带解码器；Web 受浏览器编码、CORS、混合内容和流媒体协议限制。HTTPS 页面不能保证播放 HTTP 视频。网页本地文件依赖浏览器 Blob URL，刷新后需重新选择。原生 iOS/macOS 默认限制不安全 HTTP；推荐使用 HTTPS 而不是关闭系统保护。DRM、受保护商业视频、投屏以及下载功能尚未实现。画中画目前仅实现 Android 系统级入口，其他平台不保证支持。v0.1.0 六平台 CI 构建已通过；新版以实际 CI 与真机测试为准。

## 目录
- `lib/main.dart`：应用、播放器与播放列表 UI
- `lib/media_source.dart`：网络地址校验
- `test/`：单元测试
- `scripts/bootstrap.py`：生成官方平台工程与权限配置
- `.github/workflows/check.yml`：分析、测试、Web 构建

## 克隆项目
```sh
git clone https://github.com/xuyuanbao666/omni-video-player.git omni-player
cd omni-player
python scripts/bootstrap.py
```

第三方库许可及编解码器分发要求请在公开发布安装包前审查。该项目未声明独立许可证，仓库所有者可按需选择。


## 自动打包与 Releases

[Actions](https://github.com/xuyuanbao666/omni-video-player/actions) · [Releases](https://github.com/xuyuanbao666/omni-video-player/releases)

推送 feature/** 分支的代码变更时，或在 Actions 手动执行 Six-platform build and release 时，先运行静态分析和单元测试，再执行六平台构建。开发分支仅上传构建产物；合并 main、推送版本标签、仅修改文档或工作流不会自动重复打包。PR 仍运行 Flutter checks。若修改打包配置，或直接修改 main，应手动运行六平台验证。正式发行使用独立的校验发布工作流，复用已通过验证且与合并代码一致的产物；在 main 手动运行六平台工作流可生成唯一预览版，提供 SHA256SUMS.txt，不覆盖正式版。固定使用 Flutter 3.38.9；更新 SDK 后需重新验证。

| 平台 | 产物 | 说明 |
|---|---|---|
| Android | 3 个 ABI 的 APK | 测试签名；不保证跨 CI 版本覆盖安装 |
| Windows | Setup.exe、portable.zip | x64 Inno Setup 安装包及便携版，未签名 |
| macOS | DMG | CI 主机架构；未 notarize |
| Linux | tar.gz | x64，需系统 libmpv、GTK 等运行库 |
| iOS | unsigned-app.zip | 未签名 Runner.app，不能直接安装，非 IPA |
| Web | ZIP | 解压后部署到 HTTP(S) 静态服务器 |

正式发行前应配置 Android 稳定发布密钥、Windows 代码签名、Apple Developer 证书及 provisioning profile / notarization，并核查依赖许可证。密钥只能保存在 GitHub Secrets 或其他安全密钥存储中。当前不生成已签名 iOS IPA 或商店级发布文件。

本地仅生成一个平台的 runner：`python scripts/bootstrap.py --platform windows`（可替换为 android、macos、linux、ios、web）。

## v0.2.0 新功能

- 内嵌字幕轨道选择、关闭/自动字幕与本地 UTF-8 SRT/VTT/ASS/SSA 文件（上限 2 MiB，实际格式支持由播放引擎决定；Web 支持有限）。
- 本地播放历史（最多 100 条），支持删除、清空、关闭历史和断点续播；临时 Blob/content 地址以及带查询参数、片段或用户信息的网络地址不保存；本地媒体路径失效时需重新选择。
- 当前视频帧 PNG 截图：桌面保存对话框，移动端/Web 使用系统分享或下载能力；浏览器 CORS、视频引擎和设备限制可能导致截图不可用。截图不保证包含字幕。
- 硬件加速设置：原生端重启生效，Web 由浏览器控制。
- Android 8.0+ 受支持设备可尝试系统画中画；桌面端提供应用内精简模式（不是系统置顶窗口）。iOS/macOS/Web/Linux/Windows 系统级画中画仍待实现和验证。
- 新增历史解析、容量、续播、隐私规则测试；所有平台实际体验仍需真机测试。

## v0.3.0 专业播放器开发版

- 响应式播放器、深浅主题、中英文切换、媒体库与队列切换。
- 导入文件或桌面授权目录（扫描上限 1000 个媒体文件，忽略符号链接），收藏、搜索、排序、删除；最多保存 2000 项。Web 临时地址仅会话内有效；移动端文件路径受系统访问权限限制，失效时重新导入。媒体图标为占位图，尚未生成真实缩略图。
- 双击左/右快退快进；横滑预览进度，右侧上下滑调音量，左侧上下滑调画面暗度（非系统屏幕亮度），长按 2 倍速；键盘 Space、方向键、M、F、S 控制播放。音轨切换、原比例/裁剪/拉伸、沉浸式界面；桌面沉浸模式是应用内布局，不是系统窗口全屏。
- 启动时可检查 GitHub 最新正式版，可关闭；手动检查及打开发行页面，不自动下载或安装。只在检查更新时访问固定 GitHub API。
- feature/v0.3.0 分支推送后执行六平台 CI、保存 Actions Artifacts，不自动发行；自 v0.3.1 起采用独立的校验发布工作流，不因合并重复构建。
- 新增媒体库、版本比较、隐私规则单元测试；真机体验与签名仍待验证。

## v0.3.1 玻璃 UI

默认启用应用内磨砂玻璃风格：半透明圆角面板、柔和极光渐变背景、玻璃控制栏与媒体库；深浅色主题均支持。设置中可以关闭磨砂玻璃效果以减少渲染开销。模糊范围限制在界面面板，不模糊视频纹理；不读取系统壁纸，不提供系统窗口级透明。实际性能与各平台视觉表现需真机验证。

## v0.4.0 极简玻璃界面

- 新的应用内 Omni 标志、轻量入场动画（遵循系统减少动画设置）、悬浮播放控制栏，播放时 4 秒无操作隐藏，触摸或鼠标移动恢复；高级播放选项集中在菜单。移动端独立播放器/媒体库/队列导航，桌面端双栏布局。
- 媒体库网格/列表、收藏标记、进度展示。真实缩略图仅在本地已导入视频播放时尝试截图生成，不后台解码未播放文件、不上传。缓存最多 24 张、每张不超过 64 KiB；关闭缩略图设置会清空缓存。浏览器临时文件与网络地址不缓存；不支持截图的媒体显示占位图。
- 可选视频动态取色从本地缓存的真实视频帧取样，不获取壁纸或系统颜色。分类设置（外观、播放、隐私与更新）。玻璃风格为 Flutter 模拟，非 Apple 原生 Liquid Glass 或系统窗口透明；启动器图标尚未替换。各平台视觉及性能仍需真机测试。

## v0.4.1 播放体验修复

- 强制播放器填满可用宽度；手机竖屏采用横向 16:9 播放区，未播放时显示简洁封面、文件/链接入口及最近播放，而不是狭窄黑框。
- 滑块独立局部刷新，只在松手时 seek；视频纹理 widget 保持稳定，拖动时暂停控制栏自动隐藏、缩略图截图及瞬时缓冲提示。解码器/网络跳转仍可能短暂等待，真机验证后才能判断闪屏是否完全消失。
- Android/iOS 显式选择自动、横屏、竖屏；手机全屏请求横屏，退出恢复原方向策略。系统或大屏窗口可能限制方向/系统栏控制。
- Android 同时构建通用 APK 与三种 ABI APK，增加签名校验、Android 模拟器安装/启动检查。通用包为测试签名，更新前请备份；不同构建密钥可能需要卸载旧版。真机测试仍需执行。

## v0.5.0 简洁播放界面

- 竖屏及普通窗口的控制条独立放在视频下方，时间与细进度条同一行；横屏全屏使用轻薄底部黑色渐变，点击视频切换显隐，播放时按设置自动隐藏。
- 全屏纯黑背景，遵循原视频比例；锁定后禁用触控和播放快捷键，保留解锁按钮，返回键可解除。普通模式顶部保留唯一旋转入口；快捷倍速、比例、循环、字幕、音轨及队列。
- 保留 v0.4.1 已验证的松手跳转、独立滑块状态与稳定视频纹理，用户反馈闪屏已修复。Android 真机跨型号与实际播放仍需验证。
- 固定签名暂搁置，本分支独立基于 v0.4.1；Android 仍为测试签名，升级可能需要卸载旧版（先备份）。
