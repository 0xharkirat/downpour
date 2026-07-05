import 'dart:io';

import 'package:downpour/main.dart' as app;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

// 19-second video, small and stable.
const _testUrl = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
const _testTitle = 'Me at the zoo';

/// pumpAndSettle hangs while progress bars animate, so poll with plain pumps.
Future<void> waitFor(
  PatrolTester $,
  Finder finder, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await $.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
  }
  final visibleTexts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
  throw TestFailure('Timed out waiting for $finder.\nVisible texts: $visibleTexts');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('previews then downloads a video end to end', ($) async {
    await app.main();
    await $.pump(const Duration(seconds: 1));

    // History from earlier runs would satisfy the done-state finders below;
    // start from a clean list.
    await $.pump(const Duration(seconds: 1));
    if (find.text('Clear finished').evaluate().isNotEmpty) {
      await $('Clear finished').tap(settlePolicy: SettlePolicy.noSettle);
      await $.pump(const Duration(seconds: 1));
    }

    // Step 1: paste → preview with details, no download yet.
    await Clipboard.setData(const ClipboardData(text: _testUrl));
    await $('Paste').tap(settlePolicy: SettlePolicy.noSettle);
    await waitFor($, find.textContaining(_testTitle), timeout: const Duration(minutes: 2));
    expect(find.text('Download'), findsOneWidget);

    // Step 2: explicit download.
    await $('Download').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump(const Duration(seconds: 1));

    // Done state: the tile shows open/reveal actions.
    await waitFor($, find.byIcon(FLucideIcons.play));

    // File really landed, with the quality label in the name.
    final home = Platform.environment['HOME']!;
    final downloaded = Directory('$home/Downloads')
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith(_testTitle))
        .toList();
    expect(downloaded, isNotEmpty, reason: 'downloaded file should be in ~/Downloads');
    expect(
      downloaded.any((f) => f.uri.pathSegments.last.contains('[')),
      isTrue,
      reason: 'filename should carry the quality label',
    );
    for (final file in downloaded) {
      expect(file.lengthSync(), greaterThan(100 * 1024));
      file.deleteSync(); // keep the user's Downloads clean
    }
  });

  patrolWidgetTest('settings shows engine health', ($) async {
    await app.main();
    await $.pump(const Duration(seconds: 1));

    await waitFor($, find.byIcon(FLucideIcons.settings), timeout: const Duration(minutes: 1));
    await $.tester.tap(find.byIcon(FLucideIcons.settings));
    await $.pump(const Duration(seconds: 1));

    await waitFor($, find.text('Settings'));
    // Engine card eventually reports a resolved yt-dlp with its version.
    await waitFor($, find.textContaining('yt-dlp 2'), timeout: const Duration(minutes: 2));
    // About section present.
    await waitFor($, find.textContaining('open-source video downloader'));
  });
}
