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
原生平台使用 media_kit 的原生播放引擎，支持能力取决于所带解码器；Web 受浏览器编码、CORS、混合内容和流媒体协议限制。HTTPS 页面不能保证播放 HTTP 视频。网页本地文件依赖浏览器 Blob URL，刷新后需重新选择。原生 iOS/macOS 默认限制不安全 HTTP；推荐使用 HTTPS 而不是关闭系统保护。DRM、受保护商业视频、字幕管理、播放历史、投屏、硬解设置、画中画以及下载功能尚未实现。此版本没有经过六平台真机或编译验证；以实际 CI 结果和测试为准。

## 目录
- `lib/main.dart`：应用、播放器与播放列表 UI
- `lib/media_source.dart`：网络地址校验
- `test/`：单元测试
- `scripts/bootstrap.py`：生成官方平台工程与权限配置
- `.github/workflows/check.yml`：分析、测试、Web 构建

## 克隆项目
```sh
git clone https://github.com/xuyuanbao666/-.git omni-player
cd omni-player
python scripts/bootstrap.py
```

第三方库许可及编解码器分发要求请在公开发布安装包前审查。该项目未声明独立许可证，仓库所有者可按需选择。
