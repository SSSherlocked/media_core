import 'package:flutter/painting.dart' show Offset, Rect, Size;

/// Desktop window state captured before entering picture-in-picture.
///
/// Every field is something the feature changes, so every field has to be
/// restored: leaving a user's window resizable-but-always-on-top because the
/// feature only remembered the size is worse than not remembering anything.
final class PipWindowSnapshot {
  /// Captures the window state a later [PipWindow.restore] replays.
  const PipWindowSnapshot({
    required this.bounds,
    required this.alwaysOnTop,
    required this.resizable,
    required this.skipTaskbar,
    required this.title,
    this.titleBarStyle,
  });

  /// Window size and position on screen.
  final Rect bounds;

  /// Whether the window was kept above the other apps' windows.
  final bool alwaysOnTop;

  /// Whether the viewer could resize the window by dragging an edge.
  final bool resizable;

  /// Whether the window was hidden from the taskbar and Alt-Tab.
  final bool skipTaskbar;

  /// Title bar style captured before entering PiP, so [PipWindow.restore] can
  /// put the window back exactly as it was. Null when the host does not track
  /// it.
  final Object? titleBarStyle;

  /// Window caption, so the restored window reads as the same window.
  final String title;

  @override
  String toString() => 'PipWindowSnapshot(${bounds.width}x${bounds.height} at ${bounds.topLeft})';
}

/// Desktop window operations the PiP feature needs.
///
/// This is the seam that lets the driver be tested without a live window: the
/// production implementation wraps `window_manager`'s static API, and tests
/// supply a fake. It is deliberately narrow — only the operations the small
/// window uses — so an implementation for another window toolkit has little to
/// satisfy.
abstract interface class PipWindow {
  /// Reads the current window state.
  Future<PipWindowSnapshot> capture();

  /// Applies the small-window state.
  ///
  /// [aspectRatio] locks the window to the video's shape when non-null.
  Future<void> applySmallWindow({
    required Size size,
    required Offset position,
    required double? aspectRatio,
    required bool alwaysOnTop,
    required bool resizable,
    required bool skipTaskbar,
    required String title,
  });

  /// Restores a previously captured state.
  Future<void> restore(PipWindowSnapshot snapshot);

  /// Toggles always-on-top while the small window is up.
  ///
  /// The compact window's z-order policy belongs to the feature, and hosts
  /// expose it as a user setting; a backend that cannot change the z-order
  /// while compact may ignore the call.
  Future<void> setAlwaysOnTop({required bool value});

  /// Releases or re-applies the host's normal minimum size.
  ///
  /// Needed before shrinking: a backend whose minimum size also clamps
  /// programmatic resizes (macOS `contentMinSize`) cannot reach the compact
  /// size otherwise. Backends without a minimum-size concept ignore the call.
  Future<void> setMinimumSize(Size size);

  /// Re-derives the compact window's shape for a video whose aspect changed.
  ///
  /// The small window is sized from the aspect known when PiP began, and a
  /// stream can report its real size later or switch orientation while playing.
  /// Without this the window keeps the old shape and the new picture arrives
  /// with black bars, which the shape snap then locks in.
  ///
  /// Backends that snap the window themselves re-derive the shape; a backend
  /// that relies on an OS aspect lock updates that lock instead.
  Future<void> setAspectRatio(double aspectRatio);

  /// Begins a native drag of the small window.
  ///
  /// Called while the pointer is down on the small window surface. The
  /// compact window has no title bar, so a surface-initiated drag is the only
  /// way to move it. The call returns when the drag ends. Backends whose
  /// window cannot be dragged this way ignore the call.
  Future<void> startDragging();
}
