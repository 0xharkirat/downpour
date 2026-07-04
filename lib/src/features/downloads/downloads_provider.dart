import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/ytdlp_service.dart';

class DownloadsNotifier extends Notifier<List<DownloadTask>> {
  final _handles = <String, DownloadHandle>{};
  var _nextId = 0;

  @override
  List<DownloadTask> build() {
    ref.onDispose(() {
      for (final handle in _handles.values) {
        handle.cancel();
      }
    });
    return const [];
  }

  Future<void> enqueue(String url, QualityPreset preset) async {
    final id = 'task-${_nextId++}';
    final task = DownloadTask(id: id, url: url.trim(), preset: preset, status: DownloadStatus.fetching);
    state = [task, ...state];

    final service = ref.read(ytDlpServiceProvider);
    final override = ref.read(settingsProvider).ytdlpPath;

    try {
      final info = await service.fetchInfo(task.url, override: override);
      _update(id, (t) => t.copyWith(info: info, status: DownloadStatus.downloading));

      final directory = await ref.read(downloadDirProvider.future);
      await Directory(directory).create(recursive: true);

      final handle = await service.download(
        url: task.url,
        preset: preset,
        directory: directory,
        override: override,
      );
      _handles[id] = handle;

      handle.events.listen((event) {
        switch (event) {
          case ProgressEvent(:final fraction, :final downloadedBytes, :final totalBytes, :final speed, :final etaSeconds):
            _update(
              id,
              (t) => t.copyWith(
                status: DownloadStatus.downloading,
                progress: fraction,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                speed: speed,
                etaSeconds: etaSeconds,
              ),
            );
          case ProcessingEvent():
            _update(id, (t) => t.copyWith(status: DownloadStatus.processing, progress: 1));
          case DoneEvent(:final filePath):
            _handles.remove(id);
            _update(id, (t) => t.copyWith(status: DownloadStatus.done, progress: 1, filePath: filePath));
          case FailedEvent(:final message):
            _handles.remove(id);
            _update(id, (t) {
              if (t.status == DownloadStatus.canceled) return t;
              return t.copyWith(status: DownloadStatus.error, error: message);
            });
        }
      });
    } on YtDlpException catch (e) {
      _update(id, (t) => t.copyWith(status: DownloadStatus.error, error: e.message));
    } catch (e) {
      _update(id, (t) => t.copyWith(status: DownloadStatus.error, error: '$e'));
    }
  }

  void cancel(String id) {
    _update(id, (t) => t.copyWith(status: DownloadStatus.canceled));
    _handles.remove(id)?.cancel();
  }

  void remove(String id) {
    _handles.remove(id)?.cancel();
    state = state.where((t) => t.id != id).toList();
  }

  void clearFinished() {
    state = state.where((t) => t.status.isActive).toList();
  }

  Future<void> revealInFolder(DownloadTask task) async {
    final path = task.filePath;
    if (path == null) return;
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  Future<void> openFile(DownloadTask task) async {
    final path = task.filePath;
    if (path == null) return;
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  }

  void _update(String id, DownloadTask Function(DownloadTask) transform) {
    state = [
      for (final task in state)
        if (task.id == id) transform(task) else task,
    ];
  }
}

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, List<DownloadTask>>(DownloadsNotifier.new);

final hasActiveDownloadsProvider = Provider<bool>(
  (ref) => ref.watch(downloadsProvider).any((t) => t.status.isActive),
);
