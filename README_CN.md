# JsxposedX

英文文档：[`README_EN.md`](README_EN.md)
入口页：[`README.md`](README.md)

JsxposedX 是一个面向 Xposed/LSPosed 和 Frida 工作流的 Flutter Android 应用。它把 Flutter UI 层和 Android 侧的 Xposed Hook、LSPosed service 集成、原生 bridge 模块、设备侧安装调试脚本放在同一个仓库里。

## 项目概览

- 应用名：`JsxposedX`
- 语言：英文、简体中文
- 主标签页：`Home`、`Project`、`Repository`、`Settings`
- Home 状态卡片：`AI`、`Root`、`Xposed`、`Frida`、`Zygisk module`
- Project 入口：`Quick Functions`、`AI Reverse`、`Xposed Project`、`Frida Project`

## 主要功能

- Xposed 项目页、代码编辑页、可视化编辑页
- Frida 项目页、脚本管理、目标开关、Hook 打包、编辑页
- AI Reverse 页面，包含 AI 对话、APK 上下文和 SO 分析工具
- Quick Functions 常用 Hook 开关
- Crypto audit log 和 JS editor
- SO analysis 页面，包含 `ELF Info`、`Exports`、`Imports`、`JNI`、`Strings`、`Sections`
- 内置文档位于 `assets/raws/JsxposedX_API.md`、`assets/raws/JsxposedX_API_en.md`、`assets/raws/Frida_API.md`、`assets/raws/Frida_API_en.md`
- `Repository` 标签页当前还是占位页

## Quick Functions

当前代码里的 quick-function key：

- `injectTip`
- `removeScreenshotDetection`
- `removeDialogs`
- `removeCaptureDetection`
- `modifiedVersion`
- `hideXposed`
- `hideRoot`
- `hideApps`
- `algorithmicTracking`

## 为什么构建和调试流程不同于普通 Flutter App

这个仓库不只是 Flutter UI 项目。

- `android/app/src/main/AndroidManifest.xml` 声明了 Xposed 模块元数据
- `android/app/src/main/assets/xposed_init` 指向 `com.jsxposed.x.MainHook`
- `android/app/src/main/resources/META-INF/xposed/module.prop` 设置了 `minApiVersion=53`、`targetApiVersion=100` 和 `staticScope=false`
- `android/app/src/main/kotlin/com/jsxposed/x/App.kt` 初始化 LSPosed service
- `android/app/src/main/kotlin/com/jsxposed/x/NativeProvider.kt` 注册了 `Pinia`、`StatusManagement`、`App`、`Project`、`ApkAnalysis`、`SoAnalysis`、`LSPosed`、`ZygiskFrida` 这些原生 bridge 模块

所以安装和验证流程会同时涉及 Android/Xposed 侧与 Flutter 侧。

## 环境要求

- Flutter SDK
- Android SDK 与 `adb`
- Windows PowerShell，仓库里的共享脚本基于它
- 用于 Xposed/LSPosed 流程的 root 测试环境
- 用于 Frida 流程的 Zygisk/Frida 环境

## 关键目录

- `lib/`：Flutter UI、路由、provider、功能页面
- `lib/pigeons/`：Pigeon bridge 定义
- `lib/generated/`：生成出来的 Dart bridge 代码
- `android/app/src/main/kotlin/com/jsxposed/x/`：Android 应用代码、Xposed Hook、原生 bridge 实现
- `android/app/src/main/assets/xposed_init`：Xposed 入口列表
- `android/app/src/main/resources/META-INF/xposed/module.prop`：Xposed 模块属性
- `bin/`：安装/调试 PowerShell 脚本
- `.idea/runConfigurations/`：共享 IDE 运行配置

## Pigeon 代码生成

`pigen-watch.ps1` 会监听 `lib/pigeons/**/*.dart`，并且：

- 生成 Dart bridge 文件到 `lib/generated`
- 生成 Kotlin bridge 文件到 `android/app/src/main/kotlin/...`
- 当 `*NativeImpl.kt` 不存在时创建模板文件

在仓库根目录运行：

```powershell
.\pigen-watch.ps1
```

## Debug 安装脚本

`bin/run-installDebug.ps1` 是当前仓库里的 Debug 安装脚本。

它会：

- 执行 `:app:installDebug`
- 把 `pubspec.yaml` 里的 `versionName` 和 `versionCode` 同步到 `android/local.properties`
- 从 `-DeviceId`、`ANDROID_SERIAL`、Android Studio 当前选中设备或单个已连接 `adb` 设备中解析目标设备
- 安装完成后等待一段时间，给包替换广播和 LSPosed 重扫留时间
- 可以执行 force-stop、启动应用以及 `flutter attach`

在仓库根目录运行：

```powershell
.\bin\run-installDebug.ps1
```

常用参数：

```powershell
.\bin\run-installDebug.ps1 -SkipAttach
.\bin\run-installDebug.ps1 -SkipLaunch
.\bin\run-installDebug.ps1 -DeviceId <serial>
```

## 共享 IDE 运行配置

这个仓库提交了 `.idea/runConfigurations/Flutter_installDebug.xml`。

拉取仓库后，JetBrains IDE 可以加载这个共享运行配置：

- `Flutter installDebug`

这个配置执行的是 `bin/run-installDebug.ps1 -SkipAttach`。

## 常规构建

Flutter 常规构建命令仍然可以直接使用：

```powershell
flutter build apk --debug
flutter build apk --release
```

`bin/run-installDebug.ps1` 负责设备侧的安装、启动和 attach 流程。

## 常见开发流程

```powershell
flutter pub get
.\pigen-watch.ps1
.\bin\run-installDebug.ps1
flutter attach
```

安装完成后，再到设备侧做 LSPosed/Xposed 或 Zygisk/Frida 验证。

## 说明

- 当前仓库里的共享脚本都是 PowerShell 脚本。
- 如果不是 Windows 环境，就按相同步骤手动执行。
- `flutter run` 仍然可以用于普通 Flutter 迭代，这个仓库另外保留了 Android/Xposed 的安装验证流程。