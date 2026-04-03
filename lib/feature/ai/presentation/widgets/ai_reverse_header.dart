import 'package:JsxposedX/common/widgets/custom_dIalog.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/ai_session.dart';
import 'package:JsxposedX/feature/ai/presentation/providers/chat/ai_chat_action_provider.dart';
import 'package:JsxposedX/feature/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:JsxposedX/feature/app/presentation/providers/app_query_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class AiReverseHeader extends HookConsumerWidget {
  final String packageName;

  const AiReverseHeader({super.key, required this.packageName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(aiChatActionProvider(packageName: packageName));
    final sessions = ref.read(aiChatActionProvider(packageName: packageName).notifier).getSessions();
    // final currentSession = sessions.isNotEmpty ? sessions.firstWhere((s) => s.id == chatState.currentSessionId, orElse: () => sessions.first) : null;
    final appInfoAsync = ref.watch(
      getAppByPackageNameProvider(packageName: packageName),
    );
    final activeAiConfigMeta = ref.watch(activeAiConfigMetaProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
      decoration: BoxDecoration(
        color: context.isDark
            ? context.colorScheme.surfaceContainerHigh
            : context.colorScheme.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24.r),
          bottomRight: Radius.circular(24.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: appInfoAsync.when(
        data: (app) => Row(
          children: [
            if (app?.icon != null)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: Image.memory(app!.icon, width: 42.w, height: 42.w),
                ),
              )
            else
              Icon(
                Icons.android,
                size: 40.w,
                color: context.colorScheme.primary,
              ),
            SizedBox(width: 12.w),
            Expanded(
              child: PopupMenuButton<AiSession>(
                offset: const Offset(0, 40),
                tooltip: context.l10n.aiSwitchSession,
                onSelected: (session) {
                  ref.read(aiChatActionProvider(packageName: packageName).notifier).switchSession(session.id);
                },
                itemBuilder: (context) {
                  return sessions.map((s) => PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 16.sp, color: s.id == chatState.currentSessionId ? context.colorScheme.primary : null),
                        SizedBox(width: 8.w),
                        Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  )).toList();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chatState.currentSessionId != null ? (sessions.firstWhere((s) => s.id == chatState.currentSessionId, orElse: () => sessions.first).name) : (app?.name ?? context.l10n.aiIdentifying),
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: context.textTheme.titleLarge?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, size: 20.sp, color: context.theme.hintColor),
                      ],
                    ),
                    Text(
                      packageName,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: context.theme.hintColor,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    activeAiConfigMeta.when(
                      data: (meta) => meta.isBuiltin
                          ? Padding(
                              padding: EdgeInsets.only(top: 4.h),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8.w,
                                  vertical: 3.h,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999.r),
                                  border: Border.all(
                                    color: Colors.orange.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Text(
                                  context.l10n.aiBuiltinConfigName,
                                  style: TextStyle(
                                    fontSize: 10.sp,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ):SizedBox(),

                      error: (_, __) => const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderActionButton(
                  icon: Icons.add_comment_rounded,
                  tooltip: context.l10n.aiNewSession,
                  onTap: () async {
                    final nameController = TextEditingController(text: "${context.l10n.aiNewSession} ${DateFormat('MM-dd HH:mm').format(DateTime.now())}");
                    final name = await CustomDialog.show<String>(
                      title: Text(context.l10n.aiNewSession),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.isDark ? context.colorScheme.surfaceContainerLow : Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: TextField(
                          controller: nameController,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: context.l10n.aiSessionName,
                            hintText: context.l10n.aiSessionNameHint,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: context.theme.dividerColor),
                            ),
                          ),
                        ),
                      ),
                      actionButtons: [
                        TextButton(
                          onPressed: () => SmartDialog.dismiss(),
                          child: Text(context.l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => SmartDialog.dismiss(result: nameController.text.trim()),
                          child: Text(context.l10n.confirm),
                        ),
                      ],
                    );
                    if (name != null && name.isNotEmpty) {
                      ref.read(aiChatActionProvider(packageName: packageName).notifier).createSession(name);
                    }
                  },
                ),
                SizedBox(width: 8.w),
                _HeaderActionButton(
                  icon: Icons.delete_forever_rounded,
                  tooltip: context.l10n.aiDeleteHistory,
                  color: Colors.redAccent,
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.l10n.aiDeleteConfirmTitle),
                        content: Text(context.l10n.aiDeleteConfirmContent),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.l10n.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.l10n.confirm),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      ref.read(aiChatActionProvider(packageName: packageName).notifier).deleteHistory();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        error: (_, __) => Text(context.l10n.loadFailedMessage),
        loading: () => Text(context.l10n.aiGetInfo),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: (color ?? context.colorScheme.primary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(
            icon,
            size: 20.sp,
            color: color ?? context.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
