import 'package:downpour/src/core/transcript_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _srt = '''
1
00:00:01,200 --> 00:00:03,360
All right, so here we are, in front of the
elephants

2
00:00:05,318 --> 00:00:07,974
the cool thing about these guys is that they
have really...

3
00:00:07,974 --> 00:00:12,616
really really long trunks
''';

const _vtt = '''
WEBVTT
Kind: captions
Language: en

00:01.500 --> 00:04.000 align:start position:0%
Hello <c>world</c>

00:04.000 --> 00:06.000
Hello world

01:02:03.000 --> 01:02:05.000
an hour in
''';

void main() {
  final service = TranscriptService();

  test('parses SRT blocks with multi-line text', () {
    final segments = service.parseSrt(_srt);
    expect(segments, hasLength(3));
    expect(segments.first.text, 'All right, so here we are, in front of the elephants');
    expect(segments.first.start, const Duration(seconds: 1, milliseconds: 200));
    expect(segments.first.timestamp, '00:01');
  });

  test('parses VTT with hourless timestamps, tags, and duplicate cues', () {
    final segments = service.parseSrt(_vtt);
    expect(segments, hasLength(2));
    expect(segments.first.text, 'Hello world');
    expect(segments.first.start, const Duration(seconds: 1, milliseconds: 500));
    expect(segments.last.timestamp, '1:02:03');
  });

  test('renders plain text with timestamps', () {
    final text = service.toPlainText(service.parseSrt(_srt));
    expect(text, contains('[00:01] All right'));
  });
}
