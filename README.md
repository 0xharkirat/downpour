# Downpour

Free, open-source video downloader for macOS, Windows, and Linux.
Paste a link, see the video, pick a quality, download.
Powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp), so it works with YouTube, Vimeo, Dailymotion, X, and 1800+ other sites.

No terminal, no Python, no manual installs: Downpour provisions its own download engine automatically.

## Install

Grab the latest build from [Releases](https://github.com/0xharkirat/downpour/releases).

### macOS

1. Download `Downpour-macos.zip`, unzip, and drag `Downpour.app` into Applications.
2. First launch: right-click the app and choose **Open** (the build is not notarized yet, so double-clicking is blocked by Gatekeeper).
   If macOS still refuses, run: `xattr -dr com.apple.quarantine /Applications/Downpour.app`

### Windows

1. Download `Downpour-windows-x64.zip` and extract it anywhere (for example `C:\Program Files\Downpour`).
2. Run `downpour.exe`. If SmartScreen appears, click **More info**, then **Run anyway**.

### Linux

1. Download `Downpour-linux-x64.tar.gz` and extract it: `tar -xzf Downpour-linux-x64.tar.gz`
2. Run `./downpour/downpour`.

## First launch

Downpour looks for yt-dlp and ffmpeg on your system. If they are missing, it downloads the official builds into its own data folder with progress shown in the app. Nothing is installed system-wide.

## Features

- Preview before downloading: thumbnail, title, uploader, duration.
- Quality presets: Best, 4K, 1080p, 720p, and audio-only MP3. The finished item shows what was actually downloaded.
- Live progress with speed and ETA. Cancel, open, reveal in folder, download again.
- Download history that survives restarts.
- Video transcripts from platform captions, saved as a text file next to the video.
- System notification when a download finishes.
- One-click engine updates (sites break old yt-dlp versions regularly).
- Drag a link from your browser straight onto the window.
- Light, dark, and system themes.

## Build from source

Requires Flutter 3.44+.

```sh
flutter pub get
flutter run -d macos    # or windows / linux
```

Tests:

```sh
flutter test test/                        # unit
flutter test integration_test -d macos    # end to end (downloads a real video)
```

Optional: bundle the engine into a release build so first launch needs no download at all:

```sh
flutter build macos --release
dart tool/bundle_engine.dart macos
```

## Architecture

- `lib/src/core/engine_manager.dart` provisions yt-dlp + ffmpeg: custom path, then managed copy, then bundled, then system install, then download.
- `lib/src/core/ytdlp_service.dart` runs yt-dlp and streams typed progress events parsed from `--progress-template` output.
- `lib/src/features/` holds the UI (forui + Riverpod 3 + go_router); download history lives in a drift database.

## License

MIT. Downpour is a GUI for yt-dlp. Respect the terms of service of the sites you download from and only download content you have the right to save.
