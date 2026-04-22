import 'dart:convert';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/custom_dIalog.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:JsxposedX/features/frida/presentation/providers/frida_action_provider.dart';
import 'package:JsxposedX/features/frida/presentation/providers/frida_query_provider.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/xposed_action_provider.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/xposed_query_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_toolbar/widgets/script_type_button.dart';

class CodeSaveAction extends ConsumerWidget {
  final String code;
  final String? packageName;
  final String language;

  const CodeSaveAction({
    super.key,
    required this.code,
    required this.packageName,
    required this.language,
  });

  bool get _isJavaScriptFile {
    final normalized = language.trim().toLowerCase();
    return normalized == 'javascript' || normalized == 'js';
  }

  String _resolveExportExtension() {
    final normalized = language.trim().toLowerCase();
    switch (normalized) {
      case 'javascript':
      case 'js':
        return 'js';
      case 'typescript':
      case 'ts':
        return 'ts';
      case 'dart':
        return 'dart';
      case 'java':
        return 'java';
      case 'kotlin':
      case 'kt':
        return 'kt';
      case 'xml':
        return 'xml';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'smali':
        return 'smali';
      case 'html':
        return 'html';
      case 'css':
        return 'css';
      case 'shell':
      case 'bash':
      case 'sh':
        return 'sh';
      case 'python':
      case 'py':
        return 'py';
      case 'markdown':
      case 'md':
        return 'md';
      case 'sql':
        return 'sql';
      case 'c':
        return 'c';
      case 'cpp':
      case 'c++':
        return 'cpp';
      case 'csharp':
      case 'c#':
      case 'cs':
        return 'cs';
      case 'plaintext':
      case 'text':
      case '':
        return 'txt';
      default:
        final sanitized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
        return sanitized.isEmpty ? 'txt' : sanitized;
    }
  }

  String _buildExportFileName() {
    final ext = _resolveExportExtension();
    return 'ai_export_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  String _normalizeScriptFileName(String rawName) {
    final withExtension = rawName.endsWith('.js') ? rawName : '$rawName.js';
    return withExtension;
  }

  String _normalizeXposedTraditionFileName(String rawName) {
    final fileName = _normalizeScriptFileName(rawName);
    if (fileName.startsWith('[tradition]')) {
      return fileName;
    }
    return '[tradition]$fileName';
  }

  Future<void> _exportCode(BuildContext context) async {
    await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.exportScript,
      fileName: _buildExportFileName(),
      bytes: utf8.encode(code),
    );
    if (context.mounted) {
      ToastMessage.show(context.l10n.scriptExported);
    }
  }

  Future<void> _showSaveDialog(BuildContext context, WidgetRef ref) async {
    final pkg = packageName;
    if (pkg == null || pkg.isEmpty) {
      ToastMessage.show(context.l10n.apkNoAiSession);
      return;
    }

    final nameController = TextEditingController(
      text: 'ai_hook_${DateTime.now().millisecondsSinceEpoch}.js',
    );
    String? scriptType;

    await CustomDialog.show(
      title: Text(context.l10n.saveScript, style: TextStyle(fontSize: 16.sp)),
      child: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: context.l10n.projectName,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 10.h,
                ),
              ),
              style: TextStyle(fontSize: 13.sp, fontFamily: 'monospace'),
            ),
            SizedBox(height: 14.h),
            Text(
              context.l10n.selectScriptType,
              style: TextStyle(fontSize: 13.sp),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Expanded(
                  child: ScriptTypeButton(
                    label: 'Frida',
                    icon: Icons.bolt,
                    color: const Color(0xFFFF6D00),
                    selected: scriptType == 'frida',
                    onTap: () => setState(() => scriptType = 'frida'),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ScriptTypeButton(
                    label: 'Xposed',
                    icon: Icons.extension,
                    color: const Color(0xFF7C4DFF),
                    selected: scriptType == 'xposed',
                    onTap: () => setState(() => scriptType = 'xposed'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => SmartDialog.dismiss(),
                  child: Text(context.l10n.cancel),
                ),
                SizedBox(width: 8.w),
                FilledButton(
                  onPressed: scriptType == null
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            return;
                          }

                          final fileName = scriptType == 'xposed'
                              ? _normalizeXposedTraditionFileName(name)
                              : _normalizeScriptFileName(name);

                          SmartDialog.dismiss();
                          try {
                            if (scriptType == 'frida') {
                              await ref.read(
                                createFridaScriptProvider(
                                  packageName: pkg,
                                  localPath: fileName,
                                  content: code,
                                ).future,
                              );
                              ref.invalidate(
                                fridaScriptsProvider(packageName: pkg),
                              );
                            } else {
                              if (fileName == 'hook.js' || fileName == "hook") {
                                ToastMessage.show(
                                  context.l10n.reservedScriptFileName,
                                );
                                return;
                              }
                              await ref.read(
                                createJsScriptProvider(
                                  packageName: pkg,
                                  localPath: fileName,
                                  content: code,
                                ).future,
                              );
                              ref.invalidate(
                                jsScriptsProvider(packageName: pkg),
                              );
                            }
                            if (context.mounted) {
                              ToastMessage.show(
                                context.l10n.aiScriptSavedTo(
                                  scriptType == 'frida'
                                      ? context.l10n.fridaProject
                                      : context.l10n.xposedProject,
                                  fileName,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ToastMessage.show(
                                context.l10n.aiScriptSaveFailed(e.toString()),
                              );
                            }
                          }
                        },
                  child: Text(context.l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = AiChatCompactScope.scaleOf(context);
    final isDark = context.isDark;
    final tooltip = _isJavaScriptFile
        ? context.l10n.saveScript
        : context.l10n.exportScript;
    final icon = _isJavaScriptFile
        ? Icons.save_outlined
        : Icons.file_download_outlined;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () async {
          if (_isJavaScriptFile) {
            await _showSaveDialog(context, ref);
            return;
          }
          await _exportCode(context);
        },
        borderRadius: BorderRadius.circular(4 * scale),
        child: Container(
          padding: EdgeInsets.all(4 * scale),
          child: Icon(
            icon,
            size: 16 * scale,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }
}
