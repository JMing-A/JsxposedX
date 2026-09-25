import 'dart:async';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';

import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/environments/apk_reverse_chat_environment_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/runtime/ai_chat_environment_initializer.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_runtime_state.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_input.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_list.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_conversation_drawer.dart';

import 'package:JsxposedX/features/ai/domain/repositories/script_log_repository.dart';
import 'package:JsxposedX/features/ai/presentation/providers/system/ai_system_providers.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/logcat_provider.dart';

import 'package:JsxposedX/features/apk_analysis/presentation/pages/apk_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

DateTime _logcatTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed.toUtc();
  final match = RegExp(r'^(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d+)$')
      .firstMatch(value);
  if (match == null) return DateTime.now().toUtc();
  final now = DateTime.now();
  final fraction = match.group(6)!.padRight(6, '0').substring(0, 6);
  final candidates = [now.year - 1, now.year, now.year + 1].map(
    (year) => DateTime(
      year,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(fraction.substring(0, 3)),
      int.parse(fraction.substring(3, 6)),
    ),
  );
  return candidates
      .reduce((a, b) => a.difference(now).abs() <= b.difference(now).abs() ? a : b)
      .toUtc();
}

class AiReversePage extends HookConsumerWidget {
  const AiReversePage({super.key, required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatNotifier = ref.read(
      aiChatRuntimeProvider(packageName: packageName).notifier,
    );
    final chatState = ref.watch(
      aiChatRuntimeProvider(packageName: packageName),
    );
    final sessions = ref
        .read(aiChatRuntimeProvider(packageName: packageName).notifier)
        .getSessions();
    final isZh = context.isZh;
    final environment = ref.watch(
      apkReverseChatEnvironmentProvider(
        ApkReverseChatEnvironmentArgs(packageName: packageName, isZh: isZh),
      ),
    );
    final scrollController = useScrollController();
    final pageController = usePageController();
    final sessionId = useState<String>('');
    final currentPage = useState(0);
    final showScriptConsole = useState(false);
    final selectedScriptEvent = useState<({String title, String details})?>(null);
    final scaffoldKey = useMemoized(() => GlobalKey<ScaffoldState>());
    final conversationBinding = ref.read(scriptConversationBindingProvider);
    ref.watch(logcatProvider);
    final logcat = ref.read(logcatProvider.notifier);

    useEffect(() {
      unawaited(logcat.start(packageName));
      final repository = ref.read(scriptLogRepositoryProvider);
      unawaited(
        repository
            .trimLogs(
              olderThan: DateTime.now().toUtc().subtract(
                const Duration(days: 30),
              ),
            )
            .catchError((_) {}),
      );
      return () {
        logcat.stop();
      };
    }, [logcat, packageName]);

    useEffect(() {
      conversationBinding.conversationId = chatState.currentSessionId;
      return null;
    }, [conversationBinding, chatState.currentSessionId]);

    // 预加载模型列表
    useEffect(() {
      ref.read(aiModelsProvider);
      return null;
    }, []);

    Future<void> initializeReverseSession() async {
      sessionId.value = '';
      SmartDialog.showLoading();
      await initializeAiChatEnvironment(
        notifier: chatNotifier,
        environment: environment,
        initErrorPrefix: '逆向会话初始化失败',
        onSnapshotReady: (_) {
          sessionId.value = environment.sessionId ?? '';
        },
      );
      SmartDialog.dismiss();
    }

    final followScheduled = useRef(false);
    useEffect(() {
      const followThreshold = 80.0;
      final subscription = chatNotifier.streamingContentStream.listen((
        content,
      ) {
        if (content.isEmpty || !scrollController.hasClients) {
          return;
        }
        if (scrollController.offset > followThreshold) {
          return;
        }
        if (followScheduled.value) return;
        followScheduled.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          followScheduled.value = false;
          if (!scrollController.hasClients ||
              scrollController.offset > followThreshold) {
            return;
          }
          scrollController.jumpTo(0.0);
        });
      });
      return subscription.cancel;
    }, [chatNotifier, scrollController]);

    useEffect(() {
      Future.microtask(initializeReverseSession);
      return () => unawaited(environment.dispose());
    }, [environment]);

    final lastBackPressTime = useRef<DateTime?>(null);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        final last = lastBackPressTime.value;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          Navigator.of(context).pop();
        } else {
          lastBackPressTime.value = now;
          ToastMessage.show(context.l10n.pressBackAgainToExit);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: context.isDark
              ? context.colorScheme.surfaceContainerHigh
              : context.colorScheme.surface,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24.r),
              bottomRight: Radius.circular(24.r),
            ),
          ),
          leading: _ChatDrawerButton(
            sessionCount: sessions.length,
            onTap: () => scaffoldKey.currentState?.openDrawer(),
          ),
          actions: [
          IconButton(
            tooltip: showScriptConsole.value
                ? (isZh ? '隐藏脚本控制台' : 'Hide script console')
                : (isZh ? '脚本控制台' : 'Script console'),
            onPressed: () =>
                showScriptConsole.value = !showScriptConsole.value,
            icon: Icon(
              showScriptConsole.value
                  ? Icons.terminal
                  : Icons.terminal_outlined,
            ),
          ),
        ],
          title: Text(
            chatState.currentSessionId != null && sessions.isNotEmpty
                ? sessions
                      .firstWhere(
                        (session) => session.id == chatState.currentSessionId,
                        orElse: () => sessions.first,
                      )
                      .name
                : context.l10n.aiNewSession,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: context.textTheme.titleLarge?.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        key: scaffoldKey,
        drawer: AiConversationDrawer(
          packageName: packageName,
          onSessionSelected: (id) => chatNotifier.switchSession(id),
        ),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelHeight = constraints.maxHeight < 260
                  ? constraints.maxHeight
                  : 260.0;
              return Stack(
                children: [
                  Column(
                    children: [
                      _ReverseInitBanner(
                        chatState: chatState,
                        onRetry: initializeReverseSession,
                      ),
                      Expanded(
                        child: PageView(
                          controller: pageController,
                          onPageChanged: (page) => currentPage.value = page,
                          children: [
                            AiChatList(
                              messages: chatState.visibleViewMessages,
                              scrollController: scrollController,
                              packageName: packageName,
                              customTitle: chatState.currentSessionId == null
                                  ? (isZh ? '请选择一个对话' : 'Choose a conversation')
                                  : null,
                              customSubtitle: chatState.currentSessionId == null
                                  ? (isZh
                                        ? '点击左上角的对话图标打开聊天列表'
                                        : 'Tap the conversation icon to open your chats')
                                  : null,
                            ),
                            ApkAnalysisPage(
                              packageName: packageName,
                              sessionId: sessionId.value,
                            ),
                          ],
                        ),
                      ),
                      if (currentPage.value == 0)
                        AiChatInput(
                          packageName: packageName,
                          inputTopContent: selectedScriptEvent.value == null
                              ? null
                              : _SelectedScriptRecordBar(
                                  title: selectedScriptEvent.value!.title,
                                  details: selectedScriptEvent.value!.details,
                                  onDismiss: () => selectedScriptEvent.value = null,
                                ),
                          onRetryInitialization: initializeReverseSession,
                          onOpenAnalysis: () {
                            currentPage.value = 1;
                            pageController.animateToPage(
                              1,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            );
                          },
                        ),
                    ],
                  ),
                  if (currentPage.value == 0 && showScriptConsole.value)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: panelHeight,
                      child: ScriptEventPanel(
                        packageName: packageName,
                        onEventSelected: (title, details) {
                          selectedScriptEvent.value = (title: title, details: details);
                        },
                        onClose: () => showScriptConsole.value = false,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

}

class _SelectedScriptRecordBar extends StatelessWidget {
  const _SelectedScriptRecordBar({
    required this.title,
    required this.details,
    required this.onDismiss,
  });

  final String title;
  final String details;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: context.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.content_copy_rounded,
            size: 18,
            color: context.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.isZh ? '已选中记录' : 'Record selected',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$title · $details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.isZh ? '关闭提示' : 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            color: context.colorScheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class ScriptEventPanel extends HookConsumerWidget {
  const ScriptEventPanel({
    super.key,
    required this.packageName,
    this.onEventSelected,
    this.onClose,
  });

  final String packageName;
  final void Function(String title, String details)? onEventSelected;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiChatRuntimeProvider(packageName: packageName));
    final isZh = context.isZh;
    final query = useState('');
    final scrollController = useScrollController();
    final calls = <AiToolCallPart>[
      for (final message in state.standardMessages)
        if (message.role == AiMessageRole.assistant)
          ...message.parts.whereType<AiToolCallPart>(),
    ].where((part) => _isScriptTool(part.toolCall.name)).toList();
    final results = <String, AiToolResult>{
      for (final message in state.standardMessages)
        for (final part in message.parts.whereType<AiToolResultPart>())
          part.toolResult.toolCallId: part.toolResult,
    };
    final filteredCalls = calls
        .where((part) {
          final result = results[part.toolCall.id];
          final text = [
            part.toolCall.name,
            part.toolCall.arguments.toString(),
            result?.content ?? '',
          ].join(' ').toLowerCase();
          return text.contains(query.value.trim().toLowerCase());
        })
        .toList(growable: false);

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: context.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  Icons.terminal,
                  size: 18,
                  color: context.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh
                        ? '当前对话 · 脚本工具记录'
                        : 'This conversation · Script tool records',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${calls.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: isZh ? '关闭脚本工具记录' : 'Close script tool records',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (value) => query.value = value,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: isZh
                      ? '搜索工具、脚本名或结果'
                      : 'Search tools, scripts, or results',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredCalls.isEmpty
                ? Center(
                    child: Text(
                      state.currentSessionId == null
                          ? (isZh ? '先选择一个对话' : 'Select a conversation first')
                          : (isZh
                                ? '此对话暂无脚本工作流事件'
                                : 'No script workflow events in this conversation'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: filteredCalls.length,
                    itemBuilder: (context, index) {
                      final call = filteredCalls[index].toolCall;
                      final result = results[call.id];
                      final succeeded = result?.success;
                      final color = succeeded == null
                          ? context.colorScheme.tertiary
                          : succeeded
                          ? context.colorScheme.primary
                          : context.colorScheme.error;
                      final eventText =
                          '${call.name} ${call.arguments}\n${result?.content ?? (isZh ? '执行中或结果尚未落库' : 'Running or result not yet persisted')}';
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        tileColor: context.colorScheme.primaryContainer.withValues(
                          alpha: succeeded == null ? 0.42 : 0.28,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: color.withValues(alpha: 0.35),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: Icon(
                          succeeded == null
                              ? Icons.pending_outlined
                              : succeeded
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: color,
                          size: 19,
                        ),
                        title: Text(
                          call.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          result?.content ??
                              (isZh
                                  ? '执行中或结果尚未落库'
                                  : 'Running or result not yet persisted'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          onEventSelected?.call(
                            call.name,
                            result?.content ??
                                (isZh
                                    ? '执行中或结果尚未落库'
                                    : 'Running or result not yet persisted'),
                          );
                        },
                        trailing: IconButton(
                          tooltip: isZh ? '复制到剪贴板' : 'Copy to clipboard',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.content_copy_rounded, size: 19),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: eventText));
                            ToastMessage.show(
                              isZh ? '复制成功' : 'Copied successfully',
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static bool _isScriptTool(String name) => const {
    'generate_frida_hook',
    'generate_xposed_hook',
    'save_script',
    'list_scripts',
    'toggle_script',
    'read_script',
    'delete_script',
    'read_target_logs',
    'get_script_logs',
  }.contains(name);
}

class _ReverseInitBanner extends StatelessWidget {
  const _ReverseInitBanner({required this.chatState, required this.onRetry});

  final AiChatRuntimeState chatState;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (chatState.sessionInitState == AiSessionInitState.ready) {
      return const SizedBox.shrink();
    }
    final isInitializing =
        chatState.sessionInitState == AiSessionInitState.initializing;
    final backgroundColor = isInitializing
        ? context.colorScheme.primaryContainer
        : context.colorScheme.errorContainer;
    final foregroundColor = isInitializing
        ? context.colorScheme.onPrimaryContainer
        : context.colorScheme.onErrorContainer;
    final message = isInitializing
        ? context.l10n.aiReverseSessionInitializingBanner
        : (chatState.error ?? context.l10n.aiReverseSessionInitFailedBanner);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isInitializing
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
            color: foregroundColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foregroundColor)),
          ),
          if (!isInitializing)
            TextButton(
              onPressed: onRetry,
              child: Text(
                context.l10n.retry,
                style: TextStyle(color: foregroundColor),
              ),
            ),
        ],
      ),
    );
  }
}

/// 对话列表入口图标（位于 app icon 左边）
class _ChatDrawerButton extends StatelessWidget {
  const _ChatDrawerButton({required this.sessionCount, this.onTap});

  final int sessionCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44.w,
      height: 44.w,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: context.isZh ? '对话列表' : 'Conversations',
            onPressed: onTap,
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.menu_rounded,
              size: 25.sp,
              color: context.colorScheme.primary,
            ),
          ),
          if (sessionCount > 0)
            Positioned(
              top: 2.w,
              right: 1.w,
              child: IgnorePointer(
                child: Container(
                  constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  decoration: BoxDecoration(
                    color: context.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999.r),
                    border: Border.all(
                      color: context.theme.scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    sessionCount > 99 ? '99+' : '$sessionCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colorScheme.onPrimary,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.bold,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
