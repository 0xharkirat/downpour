# Downpour

An open-source video downloader for **macOS, Windows, and Linux** in the spirit
of [Downie](https://software.charliemonroe.net/downie/), powered by
[yt-dlp](https://github.com/yt-dlp/yt-dlp) and built with Flutter.

Downie is macOS-only and paid; yt-dlp is command-line-only. Downpour is a free
desktop app for everyone else: no terminal, no Python, no manual installs.

## Zero setup

On first launch Downpour provisions its own engine automatically:

1. Uses your custom yt-dlp path if you set one in Settings.
2. Otherwise uses an existing system install of yt-dlp/ffmpeg if found.
3. Otherwise downloads the official standalone yt-dlp build (no Python
   required) and a static ffmpeg into the app's data folder, with progress
   shown in the app.

If ffmpeg can't be provisioned, downloads still work: quality presets fall
back to single-file formats and audio saves as M4A instead of MP3. A
one-click "Update yt-dlp" button keeps the managed engine current (sites break
old yt-dlp versions regularly).

## Features

- Paste a link, press Enter, get the file. Every site yt-dlp supports (1800+).
- Quality presets: Best, 4K, 1080p, 720p, and audio-only MP3.
- Live progress with speed, ETA, and size, plus cancel, open, and reveal-in-folder.
- Light, dark, and system themes ([forui](https://forui.dev) zinc design).
- Configurable download folder.

## Build from source

Requires Flutter 3.44+.

```sh
flutter pub get
flutter run -d macos    # or windows / linux
```

Engine smoke test (simulates a machine with nothing installed):

```sh
dart tool/smoke.dart
```

## Architecture

- `lib/src/core/engine_manager.dart` — provisions yt-dlp + ffmpeg: custom path
  → system install → managed download into the app support directory.
- `lib/src/core/ytdlp_service.dart` — runs yt-dlp: `-J` metadata fetch and
  downloads streamed as typed events parsed from `--progress-template` output.
- `lib/src/features/downloads/` — Riverpod 3 notifier owning the download
  queue; tasks enqueued during first-launch setup start once the engine is ready.
- `lib/src/features/home/`, `lib/src/features/settings/` — forui UI, routed
  with go_router.

## Status

Early. Desktop download flow works end to end, including the zero-install
first launch. Planned next: playlist support, format picker from the full
`-J` format list, and download history persistence.

## License

MIT. Downpour is a GUI for yt-dlp; respect the terms of service of the sites
you download from and only download content you have the right to save.
