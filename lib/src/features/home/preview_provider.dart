import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine_provider.dart';
import '../../core/models.dart';
import '../../core/settings.dart';

/// Metadata for the link currently in the input, fetched before the user
/// commits to a download. `AsyncData(null)` means no preview.
class PreviewNotifier extends AsyncNotifier<VideoInfo?> {
  @override
  Future<VideoInfo?> build() async => null;

  /// Shown when the input clearly is not a link, instead of doing nothing.
  void rejectInput() {
    state = AsyncError<VideoInfo?>(
      'That does not look like a video link. Copy the address from your browser and try again.',
      StackTrace.current,
    );
  }

  Future<void> fetch(String url) async {
    state = const AsyncLoading<VideoInfo?>();
    state = await AsyncValue.guard(() async {
      final engine = await ref.read(engineProvider.future);
      final service = ref.read(ytDlpServiceProvider);
      return service.fetchInfo(url.trim(), binary: engine.ytdlpPath);
    });
  }

  void clear() => state = const AsyncData<VideoInfo?>(null);
}

final previewProvider =
    AsyncNotifierProvider<PreviewNotifier, VideoInfo?>(PreviewNotifier.new);
