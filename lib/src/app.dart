import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'core/settings.dart';
import 'router.dart';

bool get _isTouchPlatform => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

FThemeData themeFor({required bool dark}) {
  final palette = dark ? FThemes.zinc.dark : FThemes.zinc.light;
  return _isTouchPlatform ? palette.touch : palette.desktop;
}

class DownpourApp extends ConsumerWidget {
  const DownpourApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Downpour',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      themeMode: themeMode,
      theme: themeFor(dark: false).toApproximateMaterialTheme(),
      darkTheme: themeFor(dark: true).toApproximateMaterialTheme(),
      builder: (context, child) {
        final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final dark = switch (themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        return FTheme(data: themeFor(dark: dark), child: child!);
      },
    );
  }
}
