import 'dart:async';

import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:media_core_pip/src/pip_window.dart';
import 'package:media_core_win32/media_core_win32.dart';
import 'package:window_manager/window_manager.dart';

/// [PipWindow] implemented with direct user32 calls — no plugin, no channel.
///
/// `window_manager`'s style APIs are unreliable for hosts that create their
/// window with a hidden title bar (a custom-drawn chrome): the plugin puts
/// such windows on a frameless fast path, after which its style and bounds
/// updates are silently skipped while still reporting success, so a PiP
/// transition through it leaves the window mis-sized with chrome it never
/// had. Every operation here therefore goes through [Win32WindowFfi], which
/// follows the sequence proven by the `fullscreen_window` plugin and the
/// `window_manager` sources themselves —
///
/// - skip taskbar: the `WS_EX_TOOLWINDOW` bit (what `set_skip_taskbar.cpp`
///   does), so the compact window leaves both the taskbar and Alt-Tab;
/// - resizable: the `WS_THICKFRAME` style bit, kept while compact so the
///   viewer can pick their own size;
/// - top-most: `SetWindowPos` against `HWND_TOPMOST` (via `applyBounds`);
/// - move + resize: one atomic `SetWindowPos` that also carries
///   `SWP_FRAMECHANGED` so style and bounds land together;
/// - restore: a placement snapshot (style/ex-style/placement) captured at
///   [capture] time and replayed, followed by a forced re-layout.
///
/// The custom-drawn chrome is the host's widget, so nothing here touches
/// title-bar styles; the snapshot replays whatever the window had. Free
/// user resizes are allowed while compact (`WS_THICKFRAME` stays), and a
/// snap monitor re-aligns the window shape with the video's aspect once the
/// drag settles — the contained picture never gains black bars. There is no
/// native minimum-size concept, so [setMinimumSize] is a documented no-op.
final class Win32PipWindow implements PipWindow {
  static int? _hwnd;

  Timer? _snapTimer;
  Size _lastSeenBounds = Size.zero;
  int _stableTicks = 0;

  /// The video shape the snap aligns to, or null when the host unlocked it.
  ///
  /// A 16/9 fallback here would silently re-lock a window the host asked to
  /// keep free-shaped, so "unknown" has to stay "no snap".
  double? _aspectRatio;

  int get _windowHandle {
    if (_hwnd == null || _hwnd == 0) {
      _hwnd = Win32WindowFfi.mainWindowHandle();
    }
    return _hwnd ?? 0;
  }

  @override
  Future<PipWindowSnapshot> capture() async {
    final hwnd = _windowHandle;
    final native = Win32WindowFfi.capture(hwnd);
    final bounds = Win32WindowFfi.bounds(hwnd) ?? Rect.zero;

    // Purely read-only: the native snapshot travels inside the returned
    // PipWindowSnapshot, so the caller that captured the *normal* state is
    // the one whose snapshot a later restore() replays. Caching the latest
    // capture here instead made the exit path's own capture (taken to enable
    // rollback) overwrite the entry snapshot — and restore then replayed the
    // compact window back, leaving a shrunken, taskbar-less, black window.
    return PipWindowSnapshot(
      bounds: bounds,
      alwaysOnTop: Win32WindowFfi.isTopmost(hwnd),
      resizable: Win32WindowFfi.isResizable(hwnd),
      skipTaskbar: Win32WindowFfi.isSkipTaskbar(hwnd),
      title: Win32WindowFfi.windowTitle(hwnd),
      titleBarStyle: native,
    );
  }

  @override
  Future<void> applySmallWindow({
    required Size size,
    required Offset position,
    required double? aspectRatio,
    required bool alwaysOnTop,
    required bool resizable,
    required bool skipTaskbar,
    required String title,
  }) async {
    final hwnd = _windowHandle;
    // The driver already sizes the window from the video's shape; an
    // OS-level aspect lock would fight that resize on the next size report,
    // so [aspectRatio] is deliberately not applied here — it feeds the
    // post-resize snap instead.
    _aspectRatio = aspectRatio != null && aspectRatio > 0 ? aspectRatio : null;
    Win32WindowFfi.setResizable(hwnd, resizable: resizable);
    Win32WindowFfi.setSkipTaskbar(hwnd, skip: skipTaskbar);
    Win32WindowFfi.setRoundedCorners(hwnd, round: true);
    Win32WindowFfi.applyBounds(
      hwnd,
      Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
      topmost: alwaysOnTop,
    );
    _lastSeenBounds = Size(size.width, size.height);
    _stableTicks = 0;
    _startSnapMonitor();
  }

  @override
  Future<void> restore(PipWindowSnapshot snapshot) async {
    final hwnd = _windowHandle;
    // Only the snapshot the caller captured at entry is authoritative. A
    // snapshot captured *while compact* (the rollback helper does exactly
    // that) must never win, or restore replays the compact window back.
    final native = snapshot.titleBarStyle is Win32WindowSnapshot
        ? snapshot.titleBarStyle! as Win32WindowSnapshot
        : null;

    _stopSnapMonitor();
    // The shape belongs to the session that set it: a ratio left over from a
    // locked session would otherwise keep snapping the next, unlocked one.
    _aspectRatio = null;
    if (native != null) {
      // Replays placement and every style bit captured on entry — bounds,
      // resizable, skip-taskbar and top-most included — in one sequence.
      Win32WindowFfi.restoreSnapshot(native);
      // Corner preference is not part of the placement snapshot; hand the
      // decision back to the system for the restored normal window.
      Win32WindowFfi.setRoundedCorners(hwnd, round: false);
      return;
    }

    // No native snapshot travels with this snapshot (captured by another
    // backend, or the handle was gone): reconstruct from the readable fields.
    // Styles are re-stated rather than guessed, and the title needs no
    // restore because the compact window never changed it.
    Win32WindowFfi.setSkipTaskbar(hwnd, skip: snapshot.skipTaskbar);
    Win32WindowFfi.setResizable(hwnd, resizable: snapshot.resizable);
    Win32WindowFfi.applyBounds(hwnd, snapshot.bounds, topmost: snapshot.alwaysOnTop);
  }

  /// Starts watching the compact window's bounds. While the viewer drags an
  /// edge the shape is theirs; once the bounds settle (two consecutive
  /// unchanged reads), one snap aligns the shape with the video's aspect — a
  /// landscape stream keeps its width and re-derives the height, a portrait
  /// stream keeps the height. Without this every free resize ends in black
  /// bars around the contained video.
  void _startSnapMonitor() {
    _snapTimer ??= Timer.periodic(const Duration(milliseconds: 150), (_) => _snapTick());
  }

  void _stopSnapMonitor() {
    _snapTimer?.cancel();
    _snapTimer = null;
    _stableTicks = 0;
  }

  void _snapTick() {
    final hwnd = _windowHandle;
    final bounds = Win32WindowFfi.bounds(hwnd);
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;
    final settled =
        (bounds.width - _lastSeenBounds.width).abs() < 2 && (bounds.height - _lastSeenBounds.height).abs() < 2;
    _lastSeenBounds = bounds.size;
    if (!settled) {
      _stableTicks = 0;
      return;
    }
    _stableTicks++;
    if (_stableTicks < 2) return;

    final aspectRatio = _aspectRatio;
    if (aspectRatio == null) return;

    double targetWidth;
    double targetHeight;
    if (aspectRatio >= 1.0) {
      // Landscape: the width is the long side.
      targetWidth = bounds.width;
      targetHeight = targetWidth / aspectRatio;
      if (targetHeight < 90) {
        targetHeight = 90;
        targetWidth = targetHeight * aspectRatio;
      }
    } else {
      // Portrait: the height is the long side.
      targetHeight = bounds.height;
      targetWidth = targetHeight * aspectRatio;
      if (targetWidth < 140) {
        targetWidth = 140;
        targetHeight = targetWidth / aspectRatio;
      }
    }
    if ((targetWidth - bounds.width).abs() < 3 && (targetHeight - bounds.height).abs() < 3) {
      return;
    }
    Win32WindowFfi.applyBounds(
      hwnd,
      Rect.fromLTWH(bounds.left, bounds.top, targetWidth, targetHeight),
      topmost: Win32WindowFfi.isTopmost(hwnd),
    );
    _stableTicks = 0;
    _lastSeenBounds = Size(targetWidth, targetHeight);
  }

  @override
  Future<void> setAspectRatio(double aspectRatio) async {
    if (aspectRatio <= 0 || (aspectRatio - (_aspectRatio ?? 0)).abs() < 0.01) {
      return;
    }
    _aspectRatio = aspectRatio;
    // The snap only fires after the bounds look settled, which is how a user
    // drag is told apart from a programmatic resize. A video that changed
    // shape on its own produces no drag at all, so the settle counters are
    // reset here to make the next ticks re-derive the window from the new
    // aspect instead of waiting for an interaction that is not coming.
    _stableTicks = 0;
    _lastSeenBounds = Size.zero;
  }

  @override
  Future<void> setAlwaysOnTop({required bool value}) async {
    // Bounds stay untouched: only the z-order moves.
    Win32WindowFfi.setTopmost(_windowHandle, topmost: value);
  }

  @override
  Future<void> setMinimumSize(Size size) async {
    // Everything else in this backend bypasses `window_manager` because its
    // style and bounds calls sit behind a frameless fast path for hosts with a
    // hidden title bar. A minimum size is a different animal: the plugin keeps
    // one plain value and enforces it from `WM_GETMINMAXINFO`, which is exactly
    // the platform mechanism this backend has no other way to reach, and it
    // touches no style or bounds. A zero axis releases the minimum.
    //
    // Zero handle means no runner window to constrain, which is the same
    // degradation contract every other call here follows — and unlike the FFI
    // calls, a channel call with no plugin attached would throw.
    if (_windowHandle == 0) return;
    await windowManager.setMinimumSize(size);
  }

  @override
  Future<void> startDragging() async {
    Win32WindowFfi.startDragging(_windowHandle);
  }
}
