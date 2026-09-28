import 'dart:async';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bootstrap.dart';
import 'package:JsxposedX/core/providers/locale_provider.dart';
import 'package:JsxposedX/core/providers/theme_provider.dart';
import 'package:JsxposedX/core/routes/app_router.dart';
import 'package:JsxposedX/features/home/presentation/pages/desktop_app.dart';
import 'package:JsxposedX/features/overlay_window/presentation/pages/overlay_sub_app.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_action_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/system/ai_system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // PC 端使用独立启动链，与手机端 Android 原生业务完全隔离
  if (isDesktopPlatform) {
    runApp(const ProviderScope(child: DesktopApp()));
    return;
  }
  runApp(const ProviderScope(child: MainApp()));
}

@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 悬浮窗是独立引擎，SmartDialog 未初始化，复用宿主 UI 的组件若直接调用
  // ToastMessage.show 不会显示任何内容。这里统一切到 overlay 通道提示。
  ToastMessage.override = (msg) => unawaited(ToastOverlayMessage.show(msg));
  runApp(const ProviderScope(child: OverlaySubApp()));
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(scriptLogRepositoryProvider).recoverInterruptedRuns());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(localeProvider, (_, __) {
      unawaited(
        ref.read(overlayWindowActionProvider.notifier).syncEnvironment(),
      );
    });
    ref.listen(themeProvider, (_, __) {
      unawaited(
        ref.read(overlayWindowActionProvider.notifier).syncEnvironment(),
      );
    });
    final router = ref.watch(appRouterProvider);

    return AppBootstrap(
      builder: (context, locale, lightTheme, darkTheme, themeMode) {
        return MaterialApp.router(
          title: 'JsxposedX',
          locale: locale,
          localizationsDelegates: AppBootstrap.localizationsDelegates,
          supportedLocales: AppBootstrap.supportedLocales,
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            return locale;
          },
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          builder: FlutterSmartDialog.init(),
        );
      },
    );
  }
}
