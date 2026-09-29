# JsxposedX

- Default README: [`README.md`](README.md)
- Chinese documentation: [`README_CN.md`](README_CN.md)
- Release：[`Download`](https://jsxposed.org)
  
JsxposedX is a Flutter Android application for Xposed/LSPosed and Frida workflows. It combines a
  Flutter UI layer with Android-side Xposed hooks, LSPosed service integration, native bridge
  modules, shared IDE run configurations, and PowerShell-based install/debug scripts.


This project has long adhered to free and open source sharing, aiming to lower the learning threshold and promote positive technology exchange

This project is an open source technical research tool, which is only used for legal purposes such as software debugging, program analysis, memory mechanism learning, development testing, and authorized environment research.

The author develops and publishes this project for the purpose of promoting technical exchange and learning, and does not provide any support for cheating, bypassing protection, or providing guidance on illegal use.

It is strictly prohibited to use the following acts:
• Cheating in online games, creating plug-ins, and automated illegal operations
• Interferes with the normal operation of the server or client
• Unauthorized modification of third-party program data
• Undermining the level playing field
• Any use that violates laws, regulations, or platform rules

Responsibility Description:

Users should ensure that their use of the service complies with local laws and regulations and relevant service terms. Any direct or indirect consequences arising from the use, dissemination, and secondary development of this project shall be borne by the user and have nothing to do with the author.

Open Source Notes:

The disclosure of the source code of this project does not encourage abuse. Any modification, distribution, commercialization, or illegal use by any third party based on this project has nothing to do with the original author's position.

The author reserves the right to:

The author has the right to refuse to provide support for any violating use and may adjust, suspend, or terminate the project's public content at any time.

By continuing to use this project, you are deemed to have read and agreed to this statement.

AI feature targeting

The built-in AI functions of this project are only used as general intelligent auxiliary modules, mainly used for data analysis, content interpretation, result screening, information organization, operation guidance, learning and research, and other scenarios to improve user efficiency and experience.

AI functions are auxiliary services and are not directly involved in the operation control, data destruction, permission bypass, cheat execution, or other illegal operations of any target program.

Built-in interface description

For user convenience, this project provides default AI interface access services. Users can also configure and use legally obtained third-party AI service interfaces according to their own needs, and there are no mandatory restrictions on this project.

Fee description

If some AI functions involve server resources, model call costs, computing power consumption, or interface fees, the project team may charge reasonable costs for related services. This fee only corresponds to the consumption of AI service resources and does not represent support or charges for any violating uses.

Output disclaimer

The AI output content is automatically generated based on the model and may contain errors, omissions, inaccuracies, or circumstances that may not be suitable for specific scenarios, and is for reference only. Users should make their own judgment and bear the responsibility for their final use.

Usage specifications

It is strictly prohibited to use the AI features of this project to engage in the following acts:
• Plugin production, cheat assistance, and automated illegal operations
• Hack, attack, or interfere with third-party systems
• Infringe on the legitimate rights and interests of others
• Violations of laws, regulations and platform rules

Attribution of responsibility

Any actions and consequences implemented by the user based on the AI functions of this project shall be borne by the user and have nothing to do with the project author.

Author's position

The author has always advocated for the use of AI technology in legal, legitimate, and positive learning research and efficiency improvement scenarios, and opposes any abuse.
## Project Overview

- App name: `JsxposedX`
- Locales: English and Simplified Chinese
- Main tabs: `Home`, `Project`, `Repository`, `Settings`
- Home status cards: `AI`, `Root`, `Xposed`, `Frida`, `Zygisk module`
- Project entries: `Quick Functions`, `AI Reverse`, `Xposed Project`, `Frida Project`

## Main Features

- Xposed project pages, code editor, and visual editor
- Frida project pages, script management, target switch, hook bundle, and editor
- AI Reverse page with AI chat, APK context, and SO analysis tools
- Quick Functions for common hook-related switches
- Crypto audit log and JS editor
- SO analysis pages with `ELF Info`, `Exports`, `Imports`, `JNI`, `Strings`, and `Sections`
- Built-in manuals in `assets/raws/JsxposedX_API.md`, `assets/raws/JsxposedX_API_en.md`,
  `assets/raws/Frida_API.md`, and `assets/raws/Frida_API_en.md`
- `Repository` tab is currently a placeholder page

## Related Repositories

- Frida module repository: [`dugongzi/jsxposedx-frida`](https://github.com/dugongzi/jsxposedx-frida)

## Quick Functions

Current quick-function keys in code:

- `injectTip`
- `removeScreenshotDetection`
- `removeDialogs`
- `removeCaptureDetection`
- `modifiedVersion`
- `hideXposed`
- `hideRoot`
- `hideApps`
- `algorithmicTracking`

## Why the Build and Debug Flow Differs from a Normal Flutter App

This repository is not only a Flutter UI project.

- `android/app/src/main/AndroidManifest.xml` declares Xposed module metadata
- `android/app/src/api100/` and `android/app/src/api101/` each contain a thin Xposed shell
- `android/app/src/api100/assets/xposed_init` points to `com.jsxposed.x.MainHook`
- `android/app/src/api100/resources/META-INF/xposed/module.prop` describes the `api100` shell
- `android/app/src/api101/resources/META-INF/xposed/module.prop` describes the `api101` shell
- `android/app/src/main/` keeps the shared Flutter UI, hook core, and native bridge code
- `android/app/src/main/kotlin/com/jsxposed/x/App.kt` initializes the LSPosed service
- `android/app/src/main/kotlin/com/jsxposed/x/NativeProvider.kt` registers native bridge modules for
  `Pinia`, `StatusManagement`, `App`, `Project`, `ApkAnalysis`, `SoAnalysis`, `LSPosed`, and
  `ZygiskFrida`

Because of that, installation and verification involve the Android/Xposed side as well as the
Flutter side.

## Requirements

- Flutter SDK
- Android SDK and `adb`
- Windows PowerShell for the shared scripts in this repository
- A rooted test environment for Xposed/LSPosed flows
- A Zygisk/Frida environment for Frida flows

## Key Directories

- `lib/`: Flutter UI, routes, providers, and feature pages
- `lib/pigeons/`: Pigeon bridge definitions
- `lib/generated/`: generated Dart bridge code
- `android/app/src/main/kotlin/com/jsxposed/x/`: shared Android code, hook core, and native bridge
  implementations
- `android/app/src/api100/`: `api100` shell, entry classes, and module resources
- `android/app/src/api101/`: `api101` shell, entry classes, and module resources
- `.buildScript/`: PowerShell scripts for Windows and shell scripts for macOS/Linux code generation and debug install
- `.idea/runConfigurations/`: shared IDE run configurations

## Shared IDE Run Configurations

This repository commits `.idea/runConfigurations/`.

After cloning, JetBrains IDEs can load these shared run configurations:

- `watch_pigeons` -> runs `.buildScript/pigen_watch.ps1` on Windows or `.buildScript/pigen_watch.sh` on macOS/Linux
- `build_for_xposed_type` -> runs `.buildScript/run_install_debug.ps1 -SkipAttach`

## Pigeon Code Generation

`.buildScript/pigen_watch.ps1` and `.buildScript/pigen_watch.sh` watch `lib/pigeons/**/*.dart` and:

- generates Dart bridge files into `lib/generated`
- generates Kotlin bridge files under `android/app/src/main/kotlin/...`
- creates `*NativeImpl.kt` template files when they are missing

Run it from the repository root:

```powershell
.\.buildScript\pigen_watch.ps1
```

On macOS/Linux:

```bash
./.buildScript/pigen_watch.sh
```

To generate once without starting the watcher:

```bash
./.buildScript/pigen_watch.sh --once
```

## Debug Install Script

`.buildScript/run_install_debug.ps1` and `.buildScript/run_install_debug.sh` are the debug install scripts in this repository.

It:

- runs `:app:installDebug` by default, which is mapped to `api100Debug`
- syncs `versionName` and `versionCode` from `pubspec.yaml` into `android/local.properties`
- resolves the target device from `-DeviceId`, `ANDROID_SERIAL`, the Android Studio selected device,
  or a single connected `adb` device
- uses JDK 17 and `--no-daemon` on macOS to avoid reusing a long-running, exhausted Gradle daemon
- waits after install for package replacement broadcasts and LSPosed rescan
- can force-stop the app, launch it, and run `flutter attach`

Run it from the repository root:

```powershell
.\.buildScript\run_install_debug.ps1
```

On macOS/Linux:

```bash
./.buildScript/run_install_debug.sh
```

This runs `:app:installDebug`, waits for the LSPosed rescan, cold-launches the app, and starts `flutter attach`. Running `android/gradlew` without a task only shows Gradle help; it does not build or install the app.

To install and launch without attaching automatically:

```bash
./.buildScript/run_install_debug.sh --skip-attach
```

Useful switches:

```powershell
.\.buildScript\run_install_debug.ps1 -SkipAttach
.\.buildScript\run_install_debug.ps1 -SkipLaunch
.\.buildScript\run_install_debug.ps1 -DeviceId <serial>
.\.buildScript\run_install_debug.ps1 -GradleTask :app:installApi101Debug
```

Equivalent macOS/Linux options:

```bash
./.buildScript/run_install_debug.sh --skip-attach
./.buildScript/run_install_debug.sh --skip-launch
./.buildScript/run_install_debug.sh --device-id <serial>
./.buildScript/run_install_debug.sh --java-home /path/to/jdk
./.buildScript/run_install_debug.sh --gradle-task :app:installApi101Debug
```

Select a device or show a full Gradle failure trace with:

```bash
./.buildScript/run_install_debug.sh --device-id <serial> --skip-attach
./.buildScript/run_install_debug.sh --skip-attach --gradle-arg --stacktrace
```

If the script stops after `Installing app with Gradle task ...`, the Gradle task returned a non-zero exit code. The script streams Gradle output and saves the complete log to `build/logs/install-debug.log`; add `--gradle-arg --stacktrace` for a more detailed build failure.

Extra notes:

- `installDebug` / `assembleDebug` still target `api100` by default
- install the `api101` shell explicitly with `-GradleTask :app:installApi101Debug` in PowerShell or `--gradle-task :app:installApi101Debug` in a shell

This script is used for the Xposed/LSPosed debug install flow. It is not a replacement for normal
Flutter hot reload.

## Standard Build

Standard Flutter build commands are still available:

```powershell
flutter build apk --debug
flutter build apk --release
flutter build apk --flavor api100 --release
flutter build apk --flavor api101 --release
flutter build appbundle --flavor api100 --release
flutter build appbundle --flavor api101 --release

```

If you need the release APK for `api101`, run:

```powershell
flutter build apk --flavor api101 --release
```

The output is usually:

```text
build/app/outputs/flutter-apk/app-api101-release.apk
```

If you want to build a specific Xposed shell directly, prefer the Gradle tasks:

```powershell
cd android
.\gradlew.bat :app:assembleApi100Debug
.\gradlew.bat :app:assembleApi101Debug
.\gradlew.bat :app:assembleApi100Release
.\gradlew.bat :app:assembleApi101Release

cd android
.\gradlew.bat :app:bundleApi100Release
.\gradlew.bat :app:bundleApi101Release

```

Difference between the two command styles:

- `flutter build apk --flavor api101 --release`: enters through the Flutter CLI and produces the matching flavor release APK, for example `build/app/outputs/flutter-apk/app-api101-release.apk`
- `flutter build appbundle --flavor api100 --release`: enters through the Flutter CLI, prepares Flutter/Dart assets and plugins first, then invokes the matching Android Gradle variant task
- `.\gradlew.bat :app:bundleApi100Release`: enters directly through Android Gradle, which is usually better for debugging flavors, Xposed shell resources, manifest/resource merging, and native build issues
- `.\gradlew.bat :app:assembleApi101Release`: enters directly through Android Gradle when you specifically want the matching release APK
- For the same flavor, both approaches target the same Android variant output, for example `api100` maps to `bundleApi100Release`

`.buildScript/run_install_debug.ps1` and `.buildScript/run_install_debug.sh` handle the install,
launch, and attach flow for device-side verification.

## Release Signing

Release signing is loaded from local `android/key.properties`.

- `android/key.properties` is not committed
- the keystore file is not committed
- keep signing data in local files only

## Typical Development Flow

```powershell
flutter pub get
.\.buildScript\pigen_watch.ps1
.\.buildScript\run_install_debug.ps1
flutter attach
```

On macOS/Linux:

```bash
flutter pub get
./.buildScript/pigen_watch.sh --once
./.buildScript/run_install_debug.sh --skip-attach
flutter attach
```

After installation, continue verification on the device in the LSPosed/Xposed or Zygisk/Frida
environment.

## Notes

- Use `.ps1` scripts on Windows and the corresponding `.sh` scripts on macOS/Linux; the build,
  install, and launch steps do not need to be run manually.
- `flutter run` is still available for normal Flutter iteration, while this repository also keeps an
  Android/Xposed install flow for module verification.
