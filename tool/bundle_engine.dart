// ignore_for_file: avoid_print
// Bundles yt-dlp and ffmpeg into a built app package so releases work fully
// offline-provisioned, with zero first-launch downloads.
//
// Run AFTER `flutter build <platform> --release`:
//   dart tool/bundle_engine.dart macos   [path/to/Downpour.app]
//   dart tool/bundle_engine.dart windows [path/to/build/windows/x64/runner/Release]
//   dart tool/bundle_engine.dart linux   [path/to/build/linux/x64/release/bundle]
//
// Binaries land in Contents/Resources/engine (macOS) or engine/ next to the
// executable (Windows/Linux) — the locations EngineManager.bundledDir checks.
// ffmpeg builds are GPL; ship the corresponding license notice with releases.
import 'dart:io';

const _ytdlp = {
  'macos': 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos',
  'windows': 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe',
  'linux': 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux',
};

String _ffmpegUrl(String platform) => switch (platform) {
      'macos' => 'https://ffmpeg.martin-riedl.de/redirect/latest/macos/'
          '${Platform.version.contains('arm64') ? 'arm64' : 'amd64'}/release/ffmpeg.zip',
      'windows' =>
        'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip',
      _ =>
        'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-linux64-gpl.tar.xz',
    };

const _defaultBundle = {
  'macos': 'build/macos/Build/Products/Release/Downpour.app',
  'windows': 'build/windows/x64/runner/Release',
  'linux': 'build/linux/x64/release/bundle',
};

Future<void> main(List<String> args) async {
  if (args.isEmpty || !_ytdlp.containsKey(args.first)) {
    print('usage: dart tool/bundle_engine.dart <macos|windows|linux> [bundle-path]');
    exit(64);
  }
  final platform = args.first;
  final bundle = args.length > 1 ? args[1] : _defaultBundle[platform]!;
  if (!Directory(bundle).existsSync() && !File(bundle).existsSync()) {
    print('bundle not found: $bundle — run flutter build $platform --release first');
    exit(66);
  }

  final exe = platform == 'windows' ? '.exe' : '';
  final engineDir = Directory(
    platform == 'macos' ? '$bundle/Contents/Resources/engine' : '$bundle/engine',
  );
  engineDir.createSync(recursive: true);

  print('bundling into ${engineDir.path}');

  final ytdlpFile = File('${engineDir.path}/yt-dlp$exe');
  await _fetch(_ytdlp[platform]!, ytdlpFile);
  _chmod(ytdlpFile, platform);
  print('yt-dlp: ${ytdlpFile.lengthSync()} bytes');

  final archive = File('${engineDir.path}/ffmpeg-archive');
  await _fetch(_ffmpegUrl(platform), archive);
  final extractDir = Directory('${engineDir.path}/ffmpeg-tmp')..createSync();
  final tar = Process.runSync('tar', ['-xf', archive.path, '-C', extractDir.path]);
  if (tar.exitCode != 0) {
    print('extract failed: ${tar.stderr}');
    exit(70);
  }
  final ffmpegFile = File('${engineDir.path}/ffmpeg$exe');
  final found = extractDir
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere((f) => f.uri.pathSegments.last == 'ffmpeg$exe');
  found.copySync(ffmpegFile.path);
  _chmod(ffmpegFile, platform);
  archive.deleteSync();
  extractDir.deleteSync(recursive: true);
  print('ffmpeg: ${ffmpegFile.lengthSync()} bytes');

  if (platform == 'macos') {
    print('note: re-sign the app after bundling, e.g. '
        'codesign --force --deep -s - "$bundle"');
  }
  print('done');
}

Future<void> _fetch(String url, File target) async {
  final client = HttpClient();
  try {
    var uri = Uri.parse(url);
    HttpClientResponse response;
    while (true) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      response = await request.close();
      if (response.isRedirect) {
        uri = uri.resolve(response.headers.value(HttpHeaders.locationHeader)!);
        await response.drain<void>();
        continue;
      }
      break;
    }
    if (response.statusCode != 200) {
      print('download failed (${response.statusCode}): $url');
      exit(69);
    }
    await response.pipe(target.openWrite());
  } finally {
    client.close();
  }
}

void _chmod(File file, String platform) {
  if (platform == 'windows') return;
  Process.runSync('chmod', ['+x', file.path]);
}
