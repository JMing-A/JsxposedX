# JsxposedX

- English: [`README_EN.md`](README_EN.md)
- 中文：[`README_CN.md`](README_CN.md)

JsxposedX is a Flutter Android application for Xposed/LSPosed and Frida workflows.

## Summary

- Flutter UI with Android-side Xposed hooks and LSPosed service integration
- Project entries for `Quick Functions`, `AI Reverse`, `Xposed Project`, and `Frida Project`
- Additional pages for crypto audit and SO analysis
- Pigeon bridge generation via `pigen-watch.ps1`
- Debug install flow via `bin/run-installDebug.ps1`
- Shared JetBrains run configuration in `.idea/runConfigurations/Flutter_installDebug.xml`

## Build Note

This repository is not a normal Flutter-only app. Device-side verification also involves the Android/Xposed side, so the repository includes its own PowerShell-based install/debug flow.