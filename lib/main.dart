import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/core/engine_manager.dart';
import 'src/core/engine_provider.dart';
import 'src/core/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final supportDir = await getApplicationSupportDirectory();
  final engineManager = EngineManager(
    dataDirectory: Directory('${supportDir.path}${Platform.pathSeparator}engine'),
  );

  await localNotifier.setup(appName: 'Downpour');

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1000, 700),
    minimumSize: Size(760, 540),
    center: true,
    title: 'Downpour',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        engineManagerProvider.overrideWithValue(engineManager),
      ],
      child: const DownpourApp(),
    ),
  );
}
