import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

part 'database.g.dart';

/// Finished downloads (done, error, canceled) that survive restarts.
class DownloadRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get uploader => text().nullable()();
  TextColumn get thumbnail => text().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get preset => text()();
  TextColumn get status => text()();
  TextColumn get filePath => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Cached transcript (SRT) and the sidecar file written next to the video.
  TextColumn get transcriptSrt => text().nullable()();
  TextColumn get transcriptPath => text().nullable()();

  /// What was actually downloaded, e.g. "1080p" or "audio".
  TextColumn get resolution => text().nullable()();
}

@DriftDatabase(tables: [DownloadRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(downloadRecords, downloadRecords.transcriptSrt);
            await m.addColumn(downloadRecords, downloadRecords.transcriptPath);
          }
          if (from < 3) {
            await m.addColumn(downloadRecords, downloadRecords.resolution);
          }
        },
      );

  static QueryExecutor _open() => driftDatabase(
        name: 'downpour',
        native: const DriftNativeOptions(
          databaseDirectory: getApplicationSupportDirectory,
        ),
      );

  Future<List<DownloadRecord>> allRecords() =>
      (select(downloadRecords)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Future<int> insertRecord(DownloadRecordsCompanion record) =>
      into(downloadRecords).insert(record);

  Future<void> deleteRecord(int id) =>
      (delete(downloadRecords)..where((t) => t.id.equals(id))).go();

  Future<DownloadRecord?> recordById(int id) =>
      (select(downloadRecords)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> saveTranscript(int id, String srt, String? path) =>
      (update(downloadRecords)..where((t) => t.id.equals(id))).write(
        DownloadRecordsCompanion(
          transcriptSrt: Value(srt),
          transcriptPath: Value(path),
        ),
      );

  Future<void> deleteFinished() => delete(downloadRecords).go();
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

extension DownloadRecordX on DownloadRecord {
  /// Rehydrates a history row into an immutable, inactive task.
  DownloadTask toTask() => DownloadTask(
        id: 'record-$id',
        recordId: id,
        url: url,
        preset: QualityPreset.values.asNameMap()[preset] ?? QualityPreset.best,
        status: DownloadStatus.values.asNameMap()[status] ?? DownloadStatus.done,
        info: VideoInfo(
          title: title,
          webpageUrl: url,
          thumbnail: thumbnail,
          uploader: uploader,
          durationSeconds: durationSeconds,
        ),
        filePath: filePath,
        error: error,
        resolution: resolution,
      );
}
