import 'dart:io';

/// Opens a file with its default app.
Future<void> openPath(String path) => switch (true) {
      _ when Platform.isMacOS => Process.run('open', [path]),
      _ when Platform.isWindows => Process.run('cmd', ['/c', 'start', '', path]),
      _ => Process.run('xdg-open', [path]),
    };

/// Reveals a file in the platform file manager.
Future<void> revealPath(String path) => switch (true) {
      _ when Platform.isMacOS => Process.run('open', ['-R', path]),
      _ when Platform.isWindows => Process.run('explorer', ['/select,', path]),
      _ => Process.run('xdg-open', [File(path).parent.path]),
    };
