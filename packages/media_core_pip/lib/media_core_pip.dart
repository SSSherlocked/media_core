/// Picture-in-picture for media_core.
///
/// One feature, one contract, three platform families behind it:
///
/// ```text
/// desktop → an always-on-top, aspect-shaped small window
///   Windows    → Win32PipWindow (direct user32 calls, no plugin)
///   macOS/Linux→ WindowManagerPipWindow (the window_manager plugin)
///   selection  → defaultDesktopPipWindow(), injectable per host
/// android → the platform's own PiP window (NativePipSystemPip,
///           ExoPlayer handoff; API 26+, FlutterFragmentActivity in the host)
/// iOS     → the platform's own PiP window too (NativePipSystemPip,
///           AVKit handoff; 14+, UIBackgroundModes audio in the host).
///           PiP on mobile replays the source in the system player: the host
///           supplies PipDriver.pipMediaResolver and takes playback back
///           through PipDriver.onHandoffReturn.
/// ```
///
/// [DisplayAwarePipWindow] layers the desktop placement policy (multi-
/// monitor awareness, remembered bounds, minimum-size release, rollback)
/// over whichever [PipWindow] backend the host picked.
///
/// Install it as part of a [PresentationDriverChain] so the presentation state
/// machine can route PiP requests here and route fullscreen or the in-app small
/// window elsewhere.
library;

import 'package:media_core/media_core.dart' show PresentationDriverChain;
import 'package:media_core_pip/media_core_pip.dart' show DisplayAwarePipWindow, PipWindow;

export 'package:media_core_pip/src/desktop_pip_window.dart';
export 'package:media_core_pip/src/display_pip_window.dart';
export 'package:media_core_pip/src/native_pip_system_pip.dart';
export 'package:media_core_pip/src/pip_config.dart';
export 'package:media_core_pip/src/pip_controller.dart';
export 'package:media_core_pip/src/pip_driver.dart';
export 'package:media_core_pip/src/pip_window.dart';
export 'package:media_core_pip/src/system_pip.dart';
export 'package:media_core_pip/src/win32_pip_window.dart';
export 'package:media_core_pip/src/window_manager_pip_window.dart';
