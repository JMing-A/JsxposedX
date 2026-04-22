import 'dart:async';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/presentation/providers/environments/apk_reverse_chat_environment_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/runtime/ai_chat_environment_initializer.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_runtime_state.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_input.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_list.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_reverse_header.dart';
import 'package:JsxposedX/features/apk_analysis/presentation/pages/apk_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

    final lastMessageId = useRef<String?>(null);
    useEffect(() {
      final visibleMessages = chatState.visibleMessages;
      if (visibleMessages.isNotEmpty) {
        final currentLastId = visibleMessages.last.id;
        final isNewMessage = lastMessageId.value != currentLastId;
        lastMessageId.value = currentLastId;
        if (scrollController.hasClients && isNewMessage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              scrollController.animateTo(
                0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
      return null;
    }, [chatState.visibleMessages.length]);

    useEffect(() {
      const followThreshold = 80.0;
      final subscription = chatNotifier.streamingContentStream.listen((content) {
        if (content.isEmpty || !scrollController.hasClients) {
          return;
        }
        if (scrollController.offset > followThreshold) {
          return;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) {
            return;
          }
          if (scrollController.offset > followThreshold) {
            return;
          }
          scrollController.jumpTo(0.0);
        });
      });
      return subscription.cancel;
    }, [chatNotifier, scrollController]);

    useEffect(() {
      Future.microtask(() async {
        await initializeReverseSession();
      });

      return () {
        unawaited(environment.dispose());
      };
    }, [environment]);

    final lastBackPressTime = useRef<DateTime?>(null);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }

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
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              AiReverseHeader(packageName: packageName),
              _ReverseInitBanner(
                chatState: chatState,
                onRetry: initializeReverseSession,
              ),
              Expanded(
                child: PageView(
                  controller: pageController,
                  onPageChanged: (page) {
                    currentPage.value = page;
                  },
                  children: [
                    AiChatList(
                      messages: chatState.visibleMessages,
                      scrollController: scrollController,
                      packageName: packageName,
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
        ),
      ),
    );
  }
}

class _ReverseInitBanner extends StatelessWidget {
  const _ReverseInitBanner({
    required this.chatState,
    required this.onRetry,
  });

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
            isInitializing ? Icons.hourglass_top_rounded : Icons.error_outline_rounded,
            color: foregroundColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foregroundColor),
            ),
          ),
          if (!isInitializing)
            TextButton(
              onPressed: () async {
                await onRetry();
              },
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
