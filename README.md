# Downpour

An open-source video downloader for **macOS, Windows, and Linux** in the spirit
of [Downie](https://software.charliemonroe.net/downie/), powered by
[yt-dlp](https://github.com/yt-dlp/yt-dlp) and built with Flutter.

Downie is macOS-only and paid; yt-dlp is command-line-only. Downpour is a free
desktop app for everyone else: no terminal, no Python, no manual installs.

## Zero setup

Downpour provisions its own engine automatically, resolving yt-dlp and ffmpeg
in this order:

1. A custom yt-dlp path set in Settings.
2. Binaries updated in-app (managed copies in the app's data folder).
3. Binaries bundled inside the app package (see packaging below).
4. An existing system install.
5. Downloaded on first launch: the official standalone yt-dlp build (no
   Python required) and a static ffmpeg, with progress shown in the app.

Release packages ship with both binaries bundled, so a fresh install works
offline with no first-launch download:

```sh
flutter build macos --release
dart tool/bundle_engine.dart macos
# then re-sign: codesign --force --deep -s - build/macos/Build/Products/Release/Downpour.app
```

Same for `windows` and `linux`. The script drops yt-dlp + ffmpeg into
`Contents/Resources/engine/` (macOS) or `engine/` next to the executable.
The bundled ffmpeg builds are GPL — include their license notice when
distributing.

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

## End-to-end tests (Patrol)

E2E tests live in `integration_test/` and use
[Patrol](https://patrol.leancode.co) finders. The download test drives the
real app: puts a link on the clipboard, clicks "Paste & download", waits for
the tile to reach done, and checks the file landed on disk.

Run headless (no permissions needed):

```sh
flutter test integration_test -d macos
```

The full Patrol native runner is also wired up (RunnerUITests target). It
needs a one-time grant: System Settings → Privacy & Security → Automation /
Accessibility for your terminal, because macOS gates UI automation. Then:

```sh
dart pub global activate patrol_cli
patrol test -d macos          # run under the native automator
patrol develop -d macos       # live test loop with hot restart while developing
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
