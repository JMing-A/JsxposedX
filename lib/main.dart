import 'dart:async';

import 'package:JsxposedX/common/widgets/app_bootstrap.dart';
import 'package:JsxposedX/core/providers/locale_provider.dart';
import 'package:JsxposedX/core/providers/theme_provider.dart';
import 'package:JsxposedX/core/routes/app_router.dart';
import 'package:JsxposedX/features/overlay_window/presentation/pages/overlay_sub_app.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_action_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MainApp()));
}

@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: OverlaySubApp()));
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
