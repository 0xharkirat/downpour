import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../core/database.dart';
import '../../core/engine_provider.dart';
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
    scheduleMicrotask(_loadHistory);
    return const [];
  }

  Future<void> _loadHistory() async {
    final records = await ref.read(databaseProvider).allRecords();
    final active = state.where((t) => t.recordId == null);
    state = [...active, ...records.map((r) => r.toTask())];
  }

  /// Starts a download. [info] comes from the preview step; when absent
  /// (e.g. direct submit), metadata is fetched first.
  Future<void> enqueue(String url, QualityPreset preset, {VideoInfo? info}) async {
    final id = 'task-${_nextId++}';
    final task = DownloadTask(
      id: id,
      url: url.trim(),
      preset: preset,
      status: info == null ? DownloadStatus.fetching : DownloadStatus.starting,
      info: info,
    );
    state = [task, ...state];

    final service = ref.read(ytDlpServiceProvider);

    try {
      // Waits for first-launch engine setup; tasks queue up meanwhile.
      final engine = await ref.read(engineProvider.future);

      if (info == null) {
        final fetched = await service.fetchInfo(task.url, binary: engine.ytdlpPath);
        _update(id, (t) => t.copyWith(info: fetched, status: DownloadStatus.starting));
      }

      final directory = await ref.read(downloadDirProvider.future);
      await Directory(directory).create(recursive: true);

      final handle = await service.download(
        url: task.url,
        preset: preset,
        directory: directory,
        binary: engine.ytdlpPath,
        ffmpegPath: engine.ffmpegPath,
        container: ref.read(settingsProvider).container,
      );
      _handles[id] = handle;

      handle.events.listen((event) {
        switch (event) {
          case ProgressEvent(:final fraction, :final downloadedBytes, :final totalBytes, :final speed, :final etaSeconds, :final audioTrack):
            _update(
              id,
              (t) => t.copyWith(
                status: DownloadStatus.downloading,
                progress: fraction,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                speed: speed,
                etaSeconds: etaSeconds,
                downloadingAudio: audioTrack,
              ),
            );
          case ProcessingEvent():
            _update(id, (t) => t.copyWith(status: DownloadStatus.processing, progress: 1));
          case DoneEvent(:final filePath, :final resolution):
            _handles.remove(id);
            _update(
              id,
              (t) => t.copyWith(
                status: DownloadStatus.done,
                progress: 1,
                filePath: filePath,
                resolution: resolution,
              ),
            );
            _persist(id);
            _notify(id, succeeded: true);
          case FailedEvent(:final message):
            _handles.remove(id);
            _update(id, (t) {
              if (t.status == DownloadStatus.canceled) return t;
              return t.copyWith(status: DownloadStatus.error, error: message);
            });
            _persist(id);
            _notify(id, succeeded: false);
        }
      });
    } on YtDlpException catch (e) {
      _update(id, (t) => t.copyWith(status: DownloadStatus.error, error: e.message));
      _persist(id);
    } catch (e) {
      _update(id, (t) => t.copyWith(status: DownloadStatus.error, error: '$e'));
      _persist(id);
    }
  }

  /// System notification on completion; clicking a success opens the file.
  void _notify(String id, {required bool succeeded}) {
    // Suppress during automated test runs.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task == null || task.status == DownloadStatus.canceled) return;

    final notification = LocalNotification(
      title: succeeded ? 'Download complete' : 'Download failed',
      body: succeeded
          ? '${task.displayTitle}${task.resolution == null ? '' : ' (${task.resolution})'}'
          : '${task.displayTitle}: ${task.error ?? 'unknown error'}',
    );
    if (succeeded && task.filePath != null) {
      notification.onClick = () => openFile(task);
    }
    notification.show();
  }

  Future<void> _persist(String id) async {
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task == null || task.recordId != null) return;
    final recordId = await ref.read(databaseProvider).insertRecord(
          DownloadRecordsCompanion.insert(
            url: task.url,
            title: task.displayTitle,
            uploader: Value(task.info?.uploader),
            thumbnail: Value(task.info?.thumbnail),
            durationSeconds: Value(task.info?.durationSeconds),
            preset: task.preset.name,
            status: task.status.name,
            filePath: Value(task.filePath),
            error: Value(task.error),
            resolution: Value(task.resolution),
          ),
        );
    _update(id, (t) => t.copyWith(recordId: recordId));
  }

  void cancel(String id) {
    _update(id, (t) => t.copyWith(status: DownloadStatus.canceled));
    _handles.remove(id)?.cancel();
    _persist(id);
  }

  void remove(String id) {
    _handles.remove(id)?.cancel();
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task?.recordId != null) {
      ref.read(databaseProvider).deleteRecord(task!.recordId!);
    }
    state = state.where((t) => t.id != id).toList();
  }

  void clearFinished() {
    ref.read(databaseProvider).deleteFinished();
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
