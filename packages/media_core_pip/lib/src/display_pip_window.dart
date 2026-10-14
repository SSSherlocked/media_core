import 'dart:async';

import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'package:media_core_pip/src/desktop_pip_window.dart';
import 'package:media_core_pip/src/pip_window.dart';

/// One monitor's usable area, id'd for remembered-bounds matching.
final class PipWorkArea {
  /// Names a monitor so a remembered placement can be matched back to it.
  const PipWorkArea({required this.id, required this.area});

  /// Monitor identifier as the host's display enumeration reports it. Opaque
  /// here: it is only compared, never parsed.
  final String id;

  /// The monitor's usable area, excluding OS furniture, in logical pixels.
  final Rect area;
}

/// Host-supplied display enumeration for multi-monitor placement.
typedef PipWorkAreasReader = Future<List<PipWorkArea>> Function();

/// Remembered small-window geometry; null when the host stores none or the
/// feature is off.
final class PipSavedBounds {
  /// Remembers where the viewer left the small window on a given monitor.
  const PipSavedBounds({required this.displayId, required this.bounds});

  /// Monitor the window was on, so a placement remembered for a disconnected
  /// monitor is not replayed onto another one. Empty means "no monitor recorded".
  final String displayId;

  /// The window's last size and position, in logical pixels.
  final Rect bounds;
}

/// Reads the geometry the host stored from the previous session, or null when
/// remembering is off.
typedef PipSavedBoundsReader = PipSavedBounds? Function();

/// Stores the compact window's geometry, including which monitor hosts it, so
/// the next entry can put it back where the viewer left it.
typedef PipSavedBoundsWriter = void Function(Size size, Offset position, String displayId);

/// Sizing policy for the small window, by content aspect ratio.
///
/// Landscape caps the long side at 360, portrait at 380 with a 140 floor,
/// and near-square at 280 — small enough to float over content, large
/// enough to stay legible.
Size pipSmallWindowSize(double aspectRatio) {
  final ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9;
  if (ratio > 1.05) {
    const maxSide = 360.0;
    return Size(maxSide, maxSide / ratio);
  }
  if (ratio < 0.95) {
    const maxSide = 380.0;
    var width = maxSide * ratio;
    if (width < 140) {
      width = 140;
    }
    return Size(width, width / ratio);
  }
  const maxSide = 280.0;
  return ratio >= 1.0 ? Size(maxSide, maxSide / ratio) : Size(maxSide * ratio, maxSide);
}

/// Finds the monitor that owns [position], or null when no monitor does.
///
/// A window sitting exactly on the seam between two monitors reports a corner
/// that fails strict containment on both, so a second pass tolerates the
/// rounding: without it a remembered placement on a multi-monitor desktop would
/// be treated as orphaned and re-placed from the default corner.
String? pipDisplayIdForPosition(List<PipWorkArea> displays, Offset position) {
  for (final display in displays) {
    final area = display.area;
    if (position.dx >= area.left && position.dx < area.right && position.dy >= area.top && position.dy < area.bottom) {
      return display.id;
    }
  }
  for (final display in displays) {
    final area = display.area;
    if (position.dx < area.right &&
        position.dx + 1 > area.left &&
        position.dy < area.bottom &&
        position.dy + 1 > area.top) {
      return display.id;
    }
  }
  return null;
}

/// Places the small window inside the monitor family.
///
/// A remembered placement wins when at least 48×48 of it still overlaps one
/// monitor; otherwise the monitor holding the primary work area hosts the
/// window. The size is clamped to the target area (140×90 floor) and the
/// position to its bounds, defaulting to the bottom-right corner with a
/// [placementMargin] gap.
Rect pipResolvePlacement({
  required Size requestedSize,
  required List<Rect> workAreas,
  required Rect primaryWorkArea,
  Rect? savedBounds,
  double placementMargin = 20,
}) {
  final areas = workAreas.where((area) => !area.isEmpty && area.isFinite).toList(growable: false);
  final fallbackArea = primaryWorkArea.isEmpty ? const Rect.fromLTWH(0, 0, 1280, 720) : primaryWorkArea;
  final candidates = areas.isEmpty ? <Rect>[fallbackArea] : areas;
  final validSaved = savedBounds != null && savedBounds.isFinite && !savedBounds.isEmpty ? savedBounds : null;

  Rect target;
  if (validSaved != null) {
    target = candidates.firstWhere((area) {
      final overlap = validSaved.intersect(area);
      return overlap.width >= 48 && overlap.height >= 48;
    }, orElse: () => Rect.zero);
  } else {
    target = Rect.zero;
  }
  if (target == Rect.zero) {
    target = candidates.firstWhere(
      (area) => area.overlaps(fallbackArea) || area.contains(fallbackArea.center),
      orElse: () => candidates.first,
    );
  }

  final requested = validSaved?.size ?? requestedSize;
  final minWidth = target.width < 140 ? target.width : 140.0;
  final minHeight = target.height < 90 ? target.height : 90.0;
  final width = requested.width.clamp(minWidth, target.width);
  final height = requested.height.clamp(minHeight, target.height);
  final defaultLeft = target.right - width - placementMargin;
  final defaultTop = target.bottom - height - placementMargin;
  final left = (validSaved?.left ?? defaultLeft).clamp(target.left, target.right - width);
  final top = (validSaved?.top ?? defaultTop).clamp(target.top, target.bottom - height);
  return Rect.fromLTWH(left, top, width, height);
}

/// Desktop small window with the full placement policy: multi-monitor
/// awareness, remembered bounds with display matching, minimum-size
/// release, host rollback on failure and a serialized operation queue.
///
/// Every actual window operation is delegated to an injected [PipWindow] —
/// the platform backend ([defaultDesktopPipWindow]: Win32 on Windows,
/// `window_manager` on macOS and Linux) or a host-supplied one. This class
/// owns only the policy around it, which is why the driver can be tested
/// without a window and the backend can be swapped per platform.
///
/// Display enumeration is injected so hosts with their own screen plugin
/// stay dependency-free; single-display hosts can omit the reader and the
/// current window's monitor bounds stand in for the work area.
final class DisplayAwarePipWindow implements PipWindow {
  /// Wraps a window backend in the placement policy.
  ///
  /// [windowBuilder] is called on first use, not in here, so a host can build
  /// this object before its window exists (and a test can hand in a fake).
  /// [alwaysOnTop], when supplied, overrides what each request asks for: the
  /// host's own z-order setting wins over the caller.
  DisplayAwarePipWindow({
    PipWindow Function()? windowBuilder,
    this.workAreasReader,
    this.readSavedBounds,
    this.writeSavedBounds,
    bool Function()? alwaysOnTop,
    this.normalMinSize = Size.zero,
    this.defaultSize = const Size(1280, 720),
    this.placementMargin = 20,
  }) : _windowBuilder = windowBuilder ?? defaultDesktopPipWindow,
       _alwaysOnTop = alwaysOnTop;

  final PipWindow Function() _windowBuilder;

  /// Enumerates the monitors to place the window among. Null on a
  /// single-display host, which then gets the current view's bounds as its only
  /// work area.
  final PipWorkAreasReader? workAreasReader;

  /// Recalls the geometry the viewer left the small window with.
  final PipSavedBoundsReader? readSavedBounds;

  /// Records the geometry for the next entry.
  final PipSavedBoundsWriter? writeSavedBounds;
  final bool Function()? _alwaysOnTop;

  /// The host's own window minimum, re-applied when leaving the small window so
  /// the normal window keeps its floor.
  final Size normalMinSize;

  /// Assumed window size while the backend reports none.
  final Size defaultSize;

  /// Gap left between the compact window and the monitor edge it snaps to.
  final double placementMargin;

  PipWindow? _windowInstance;

  /// The backend every window operation is delegated to.
  PipWindow get window => _windowInstance ??= _windowBuilder();

  final List<Future<void>> _opQueue = [];
  PipWindowSnapshot? _savedSnapshot;
  bool _compact = false;

  /// Whether the compact window is up, which is what tells a late call whether
  /// it may touch the window at all.
  bool get isCompact => _compact;

  @override
  Future<void> setAlwaysOnTop({required bool value}) {
    return _serialize(() async {
      if (!_compact) return;
      await window.setAlwaysOnTop(value: value);
    });
  }

  @override
  Future<void> setAspectRatio(double aspectRatio) {
    return _serialize(() async {
      if (!_compact) return;
      await window.setAspectRatio(aspectRatio);
    });
  }

  @override
  Future<void> setMinimumSize(Size size) => window.setMinimumSize(size);

  @override
  Future<void> startDragging() async {
    if (!_compact) return;
    await window.startDragging();
  }

  /// Persists the current small-window geometry when remembered bounds are on.
  Future<void> captureGeometry() {
    return _serialize(() async {
      if (!_compact) return;
      final saved = readSavedBounds?.call();
      if (saved == null) return;
      final current = await window.capture();
      final position = current.bounds.topLeft;
      final displays = await _workAreas();
      final displayId =
          pipDisplayIdForPosition(displays, position) ?? (displays.isEmpty ? null : _displayOfCurrentView(displays));
      if (displayId == null) return;
      writeSavedBounds?.call(current.bounds.size, position, displayId);
    });
  }

  @override
  Future<PipWindowSnapshot> capture() => window.capture();

  @override
  Future<void> applySmallWindow({
    required Size size,
    required Offset position,
    required double? aspectRatio,
    required bool alwaysOnTop,
    required bool resizable,
    required bool skipTaskbar,
    required String title,
  }) {
    // The ratio travels unchanged: null is the host asking for a freely
    // resizable shape, and only the placement math below needs a concrete one.
    return _serialize(() => _enter(aspectRatio, size, alwaysOnTop, skipTaskbar));
  }

  @override
  Future<void> restore(PipWindowSnapshot snapshot) {
    return _serialize(_exit);
  }

  Future<void> _enter(double? shapeAspectRatio, Size requestedSize, bool alwaysOnTopOverride, bool skipTaskbar) async {
    if (_compact) return;
    final window = this.window;
    final normal = await window.capture();
    // Sizing must always start from a real ratio, even when the shape is
    // unlocked: the remembered bounds and the default size are expressed as a
    // long side plus the video's aspect.
    final aspectRatio = shapeAspectRatio ?? requestedSize.width / requestedSize.height;

    final displays = await _workAreas();
    final currentId = pipDisplayIdForPosition(displays, normal.bounds.topLeft);
    final current = displays.firstWhere(
      (display) => display.id == currentId,
      orElse: () => displays.isEmpty ? PipWorkArea(id: '', area: _currentViewWorkArea()) : displays.first,
    );

    final saved = readSavedBounds?.call();
    final savedMatches = saved != null && (saved.displayId.isEmpty || saved.displayId == current.id);
    // The remembered size is the user's scale, not a fixed shape: the short
    // side always follows the CURRENT video's aspect. A size remembered on a
    // landscape stream must not letterbox a portrait one (and vice versa) —
    // a box whose shape drifts from the picture shows nothing but black bars.
    PipSavedBounds? matchedSaved;
    if (saved != null && savedMatches && shapeAspectRatio == null) {
      // Unlocked shape: the remembered bounds ARE the shape the viewer picked,
      // so they are replayed as they are. Re-deriving the video's aspect here
      // would undo a squashed window on every entry into the small window.
      matchedSaved = saved;
    } else if (saved != null && savedMatches) {
      // The user's scale is the remembered LONG side — it carries across
      // orientation changes (a size picked on a portrait stream applies to
      // the landscape stream's long side too).
      final scale = saved.bounds.width > saved.bounds.height ? saved.bounds.width : saved.bounds.height;
      // The floors are aspect-exact: when one side bottoms out the other
      // follows down, so a smaller pick still yields a video-shaped window.
      const minWidthFloor = 140.0;
      const minHeightFloor = 90.0;
      final Size followed;
      if (aspectRatio >= 1.0) {
        var width = scale.clamp(minWidthFloor, double.infinity);
        var height = width / aspectRatio;
        if (height < minHeightFloor) {
          height = minHeightFloor;
          width = height * aspectRatio;
        }
        followed = Size(width, height);
      } else {
        var height = scale.clamp(minHeightFloor, double.infinity);
        var width = height * aspectRatio;
        if (width < minWidthFloor) {
          width = minWidthFloor;
          height = width / aspectRatio;
        }
        followed = Size(width, height);
      }
      matchedSaved = PipSavedBounds(
        displayId: saved.displayId,
        bounds: Rect.fromLTWH(saved.bounds.left, saved.bounds.top, followed.width, followed.height),
      );
    }
    final placement = pipResolvePlacement(
      requestedSize: pipSmallWindowSize(aspectRatio),
      workAreas: [for (final display in displays) display.area],
      primaryWorkArea: current.area,
      savedBounds: matchedSaved?.bounds,
      placementMargin: placementMargin,
    );

    final pinOnTop = _alwaysOnTop?.call() ?? alwaysOnTopOverride;
    try {
      // Release the minimum size before shrinking: a backend whose minimum
      // size also clamps programmatic resizes (macOS contentMinSize) cannot
      // reach the compact size otherwise. A no-op on backends without the
      // concept.
      await window.setMinimumSize(Size.zero);
      await window.applySmallWindow(
        size: placement.size,
        position: placement.topLeft,
        aspectRatio: shapeAspectRatio,
        alwaysOnTop: pinOnTop,
        resizable: true,
        // The host's choice travels through: hiding the compact window from the
        // taskbar (and Alt-Tab) is a host decision, and overriding it here made
        // [PipConfig.skipTaskbar] unreachable for every host that wrapped its
        // backend in this placement policy.
        skipTaskbar: skipTaskbar,
        title: normal.title,
      );
      final landedId = pipDisplayIdForPosition(displays, placement.topLeft) ?? current.id;
      writeSavedBounds?.call(placement.size, placement.topLeft, landedId);
    } catch (error, stackTrace) {
      await _rollbackToNormal(window, normal);
      Error.throwWithStackTrace(error, stackTrace);
    }

    _savedSnapshot = normal;
    _compact = true;
  }

  Future<void> _exit() async {
    if (!_compact) return;
    final window = this.window;
    final saved = _savedSnapshot;
    if (saved == null) return;
    final compact = await window.capture();
    try {
      await window.setMinimumSize(normalMinSize);
      await window.restore(saved);
    } catch (error, stackTrace) {
      await _rollbackToCompact(window, compact);
      Error.throwWithStackTrace(error, stackTrace);
    }
    _savedSnapshot = null;
    _compact = false;
  }

  Future<void> _rollbackToNormal(PipWindow window, PipWindowSnapshot normal) async {
    // Best effort: every step stands alone, and one failure must not keep
    // the later ones from running.
    final steps = <Future<void> Function()>[() => window.setMinimumSize(normalMinSize), () => window.restore(normal)];
    for (final step in steps) {
      try {
        await step();
      } on Object catch (_) {}
    }
  }

  Future<void> _rollbackToCompact(PipWindow window, PipWindowSnapshot compact) async {
    final steps = <Future<void> Function()>[() => window.setMinimumSize(Size.zero), () => window.restore(compact)];
    for (final step in steps) {
      try {
        await step();
      } on Object catch (_) {}
    }
  }

  Future<List<PipWorkArea>> _workAreas() async {
    final reader = workAreasReader;
    if (reader != null) {
      final areas = await reader();
      if (areas.isNotEmpty) return areas;
    }
    return [PipWorkArea(id: '', area: _currentViewWorkArea())];
  }

  Rect _currentViewWorkArea() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return const Rect.fromLTWH(0, 0, 1280, 720);
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return Rect.fromLTWH(0, 0, size.width, size.height);
  }

  String _displayOfCurrentView(List<PipWorkArea> displays) => displays.first.id;

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _opQueue.isEmpty ? operation() : _opQueue.last.then((_) => operation());
    _opQueue.add(result);
    unawaited(
      result
          .whenComplete(() {
            _opQueue.remove(result);
          })
          .catchError((_) {}),
    );
    return result;
  }
}
