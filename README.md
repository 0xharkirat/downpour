# Downpour

An open-source, cross-platform video downloader in the spirit of
[Downie](https://software.charliemonroe.net/downie/), powered by
[yt-dlp](https://github.com/yt-dlp/yt-dlp) and built with Flutter.

Downie is macOS-only and yt-dlp is CLI-only. Downpour puts a clean GUI on top of
yt-dlp and runs on macOS, Windows, and Linux, with iOS and Android targets
scaffolded for a future mobile engine.

## Features

- Paste a link, press Enter, get the file. Supports every site yt-dlp supports (1800+).
- Quality presets: Best, 4K, 1080p, 720p, and audio-only MP3.
- Live progress with speed, ETA, and size, plus cancel, open, and reveal-in-folder.
- Light, dark, and system themes ([forui](https://forui.dev) zinc design).
- Configurable download folder and yt-dlp binary path; the binary is
  auto-detected from common install locations and your login shell PATH.

## Requirements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp#installation) on your PATH
  (`brew install yt-dlp`, `winget install yt-dlp`, or `pipx install yt-dlp`)
- [ffmpeg](https://ffmpeg.org) for merging video+audio streams and MP3 extraction
  (`brew install ffmpeg` / `winget install ffmpeg`)
- Flutter 3.44+ to build from source

## Build

```sh
flutter pub get
flutter run -d macos    # or windows / linux
```

## Architecture

- `lib/src/core/ytdlp_service.dart` — thin wrapper over the yt-dlp CLI: binary
  discovery, `-J` metadata fetch, and downloads streamed as typed events parsed
  from `--progress-template` output.
- `lib/src/features/downloads/` — Riverpod 3 notifier owning the download queue;
  each task holds an immutable snapshot updated from engine events.
- `lib/src/features/home/`, `lib/src/features/settings/` — forui UI, routed with
  go_router.

Mobile platforms cannot spawn CLI binaries, so the engine is isolated behind a
small service layer; an alternative engine (for example `youtube_explode_dart`)
can back iOS/Android later without touching the UI.

## Status

Early. Desktop download flow works end to end. Planned next: playlist support,
format picker from the full `-J` format list, download history persistence, and
a mobile engine.

## License

MIT. Downpour is a GUI for yt-dlp; respect the terms of service of the sites
you download from and only download content you have the right to save.
