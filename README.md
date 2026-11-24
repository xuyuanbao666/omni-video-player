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

每次推送 main、推送 v* 标签，或在 Actions 手动执行 Six-platform build and release 时，先运行静态分析和单元测试，然后在各平台的 GitHub 托管 runner 并行打包。所有六个平台均成功后才发布预览版 Release，且提供 SHA256SUMS.txt。main 每次构建使用唯一预览标签，不会覆盖旧版本。固定使用 Flutter 3.38.9；更新 SDK 后需重新验证。

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
