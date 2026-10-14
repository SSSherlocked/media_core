import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_core_pip/src/pip_driver.dart' show PipDriver;
import 'package:media_core_pip/src/pip_window.dart';
import 'package:media_core_pip/src/win32_pip_window.dart';
import 'package:media_core_pip/src/window_manager_pip_window.dart';

/// Builds the best [PipWindow] backend for the host platform.
///
/// - **Windows** — [Win32PipWindow]: direct user32 calls. The plugin's style
///   APIs sit behind a frameless fast path for hosts with a hidden title
///   bar, and their `setSkipTaskbar` has shipped crash reports; the native
///   path has neither problem.
/// - **macOS, Linux** — [WindowManagerPipWindow]: the frameless fast path is
///   a Windows-only behaviour, so the plugin stays the pragmatic backend
///   there.
/// - **anything else** — [UnsupportedError]: a desktop small window needs a
///   real window to shrink; mobile platforms are served by the system-PiP
///   path ([PipDriver]'s mobile branch), and iOS has no system PiP API
///   reachable for arbitrary Flutter content at all.
///
/// The platform flags are injectable so the selection is testable on every
/// host.
PipWindow defaultDesktopPipWindow({bool? isWindows, bool? isMacOS, bool? isLinux}) {
  final windows = isWindows ?? (!kIsWeb && Platform.isWindows);
  final macos = isMacOS ?? (!kIsWeb && Platform.isMacOS);
  final linux = isLinux ?? (!kIsWeb && Platform.isLinux);

  if (windows) {
    return Win32PipWindow();
  }
  if (macos || linux) {
    return const WindowManagerPipWindow();
  }
  throw UnsupportedError('Desktop picture-in-picture needs Windows, macOS or Linux.');
}
