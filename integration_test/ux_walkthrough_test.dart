// ignore_for_file: avoid_print
// Exploratory UX walkthrough, driven like a first-time user. Skipped in the
// stable suite because it depends on third-party sites; run manually with:
//   flutter test integration_test/ux_walkthrough_test.dart -d macos --dart-define=WALKTHROUGH=true
import 'package:downpour/main.dart' as app;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

Future<void> waitFor(
  PatrolTester $,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await $.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

List<String> visibleTexts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .toList();

void main() {
  if (!const bool.fromEnvironment('WALKTHROUGH')) return;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('walkthrough: garbage input, wrong url, vimeo download', ($) async {
    await app.main();
    await $.pump(const Duration(seconds: 2));

    // 1. Type garbage with no dot and press Enter.
    await $(FTextField).enterText('hello world');
    await $.tester.testTextInput.receiveAction(TextInputAction.go);
    await $.pump(const Duration(seconds: 2));
    print('WALKTHROUGH after garbage: ${visibleTexts()}');

    // 2. A real site that is not a video platform.
    await Clipboard.setData(const ClipboardData(text: 'https://example.com'));
    await $('Paste').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump(const Duration(seconds: 8));
    print('WALKTHROUGH after example.com: ${visibleTexts()}');

    // 3. A Vimeo link end to end.
    await Clipboard.setData(const ClipboardData(text: 'https://vimeo.com/76979871'));
    await $('Paste').tap(settlePolicy: SettlePolicy.noSettle);
    await waitFor($, find.textContaining('The New Vimeo Player'));
    print('WALKTHROUGH vimeo preview visible');
    await $('Download').tap(settlePolicy: SettlePolicy.noSettle);
    await waitFor($, find.byIcon(FLucideIcons.play), timeout: const Duration(minutes: 4));
    print('WALKTHROUGH vimeo download done: ${visibleTexts()}');
  });
}
