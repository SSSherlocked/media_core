/// Only 64-bit Windows is bound (`GetWindowLongPtrW`); that matches the
/// shipped builds. All calls go straight to user32 from Dart via FFI —
/// no plugin, no channel.
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart' show Rect;

/// Direct user32 window-state operations for the desktop presentations.
///
/// `window_manager`'s own style APIs are unreliable for this class of hosts:
/// a window that is created with a hidden title bar (a custom-drawn chrome)
/// is put on a frameless fast path inside the plugin, after which its native
/// `setFullScreen`/`setBounds` implementations silently skip style and
/// bounds updates while still reporting success. The fullscreen and PiP
/// presentations must not depend on that state machine.
///
/// These bindings follow the proven sequence used by the `fullscreen_window`
/// plugin: snapshot the window's style/ex-style/placement once, mutate the
/// style bits, and move the window with a single `SetWindowPos` that carries
/// `SWP_FRAMECHANGED` so the frame change is applied atomically with the new
/// bounds. Restoration replays the snapshot and then issues a redundant
/// `SetWindowPos`, because Flutter's layout is not always correct after the
/// frame change.
///

const int _gwlStyle = -16;
const int _gwlExStyle = -20;
const int _wsCaption = 0x00C00000;
const int _wsThickframe = 0x00040000;
const int _wsMaximize = 0x01000000;
const int _wsExTopmost = 0x00000008;
const int _wsExToolwindow = 0x00000080;
const int _wsExDlgModalFrame = 0x00000001;
const int _wsExWindowEdge = 0x00000100;
const int _wsExClientEdge = 0x00000200;
const int _wsExStaticEdge = 0x00020000;
const int _hwndTopmost = -1;
const int _hwndNotopmost = -2;
const int _hwndNoZorderChange = 0;
const int _swpNoSize = 0x0001;
const int _swpNoMove = 0x0002;
const int _swpNoZorder = 0x0004;
const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;
const int _swpShowWindow = 0x0040;
const int _monitorDefaultToNearest = 2;
const int _wmSyscommand = 0x0112;
const int _scRestore = 0xF120;
const int _dwmwaWindowCornerPreference = 33;
const int _dwmwcpDefault = 0;
const int _dwmwcpRound = 2;
const int _wmNclbuttondown = 0x00A1;
const int _htcaption = 2;
const int _wmGettext = 0x000D;
const int _wmGettextlength = 0x000E;

typedef _Dword = UnsignedInt;
typedef _Long = Int32;
typedef _LongPtr = IntPtr;
typedef _Hwnd = IntPtr;
typedef _Hmonitor = IntPtr;
typedef _Bool32 = Int32;

final class _Rect extends Struct {
  @_Long()
  external int left;
  @_Long()
  external int top;
  @_Long()
  external int right;
  @_Long()
  external int bottom;
}

final class _Point extends Struct {
  @_Long()
  external int x;
  @_Long()
  external int y;
}

final class _WindowPlacement extends Struct {
  @_Dword()
  external int length;
  @_Dword()
  external int flags;
  @_Dword()
  external int showCmd;
  external _Point ptMinPosition;
  external _Point ptMaxPosition;
  external _Rect rcNormalPosition;
}

final class _MonitorInfo extends Struct {
  @_Dword()
  external int cbSize;
  external _Rect rcMonitor;
  external _Rect rcWork;
  @_Dword()
  external int dwFlags;
}

typedef _FindWindowWNative = _Hwnd Function(Pointer<Utf16> className, Pointer<Utf16> windowName);
typedef _FindWindowWDart = int Function(Pointer<Utf16> className, Pointer<Utf16> windowName);
typedef _FindWindowExWNative =
    _Hwnd Function(_Hwnd parent, _Hwnd after, Pointer<Utf16> className, Pointer<Utf16> windowName);
typedef _FindWindowExWDart = int Function(int parent, int after, Pointer<Utf16> className, Pointer<Utf16> windowName);
typedef _GetWindowThreadProcessIdNative = _Dword Function(_Hwnd hwnd, Pointer<_Dword> processId);
typedef _GetWindowThreadProcessIdDart = int Function(int hwnd, Pointer<_Dword> processId);
typedef _GetWindowLongPtrWNative = _LongPtr Function(_Hwnd hwnd, _LongPtr index);
typedef _GetWindowLongPtrWDart = int Function(int hwnd, int index);
typedef _SetWindowLongPtrWNative = _LongPtr Function(_Hwnd hwnd, _LongPtr index, _LongPtr value);
typedef _SetWindowLongPtrWDart = int Function(int hwnd, int index, int value);
typedef _SetWindowPosNative =
    _Bool32 Function(_Hwnd hwnd, _Hwnd after, _Long x, _Long y, _Long cx, _Long cy, _Dword flags);
typedef _SetWindowPosDart = int Function(int hwnd, int after, int x, int y, int cx, int cy, int flags);
typedef _GetWindowPlacementNative = _Bool32 Function(_Hwnd hwnd, Pointer<_WindowPlacement> placement);
typedef _GetWindowPlacementDart = int Function(int hwnd, Pointer<_WindowPlacement> placement);
typedef _SetWindowPlacementNative = _Bool32 Function(_Hwnd hwnd, Pointer<_WindowPlacement> placement);
typedef _SetWindowPlacementDart = int Function(int hwnd, Pointer<_WindowPlacement> placement);
typedef _MonitorFromWindowNative = _Hmonitor Function(_Hwnd hwnd, _Dword flags);
typedef _MonitorFromWindowDart = int Function(int hwnd, int flags);
typedef _GetMonitorInfoWNative = _Bool32 Function(_Hmonitor monitor, Pointer<_MonitorInfo> info);
typedef _GetMonitorInfoWDart = int Function(int monitor, Pointer<_MonitorInfo> info);
typedef _IsZoomedNative = _Bool32 Function(_Hwnd hwnd);
typedef _IsZoomedDart = int Function(int hwnd);
typedef _GetWindowRectNative = _Bool32 Function(_Hwnd hwnd, Pointer<_Rect> rect);
typedef _GetWindowRectDart = int Function(int hwnd, Pointer<_Rect> rect);
typedef _SendMessageWNative = _LongPtr Function(_Hwnd hwnd, _Dword msg, _LongPtr wparam, _LongPtr lparam);
typedef _SendMessageWDart = int Function(int hwnd, int msg, int wparam, int lparam);
typedef _DwmSetWindowAttributeNative = _LongPtr Function(_Hwnd hwnd, _Dword attr, Pointer<_Dword> value, _Dword size);
typedef _DwmSetWindowAttributeDart = int Function(int hwnd, int attr, Pointer<_Dword> value, int size);
typedef _ReleaseCaptureNative = _Bool32 Function();
typedef _ReleaseCaptureDart = int Function();
typedef _GetCurrentProcessIdNative = _Dword Function();
typedef _GetCurrentProcessIdDart = int Function();

/// A captured window placement, sufficient to put the window back exactly
/// where it was.
final class Win32WindowSnapshot {
  const Win32WindowSnapshot._(this.hwnd, this._style, this._exStyle, this._maximized, this._placement);

  /// The window the snapshot belongs to.
  final int hwnd;
  final int _style;
  final int _exStyle;
  final bool _maximized;

  // length, flags, showCmd, min(x,y), max(x,y), rect(l,t,r,b)
  final List<int> _placement;
}

/// The Win32 window operations the presentations are built on.
abstract final class Win32WindowFfi {
  /// Whether these bindings can be used on this platform.
  static bool get isSupported => Platform.isWindows;

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary? _dwmapi = Platform.isWindows ? DynamicLibrary.open('dwmapi.dll') : null;

  static final _ReleaseCaptureDart _releaseCapture = _user32.lookupFunction<_ReleaseCaptureNative, _ReleaseCaptureDart>(
    'ReleaseCapture',
  );
  static final _DwmSetWindowAttributeDart? _dwmSetWindowAttribute = _dwmapi
      ?.lookupFunction<_DwmSetWindowAttributeNative, _DwmSetWindowAttributeDart>('DwmSetWindowAttribute');
  static final _GetCurrentProcessIdDart _getCurrentProcessId = _kernel32
      .lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>('GetCurrentProcessId');
  static final _FindWindowWDart _findWindow = _user32.lookupFunction<_FindWindowWNative, _FindWindowWDart>(
    'FindWindowW',
  );
  static final _FindWindowExWDart _findWindowEx = _user32.lookupFunction<_FindWindowExWNative, _FindWindowExWDart>(
    'FindWindowExW',
  );
  static final _GetWindowThreadProcessIdDart _getWindowThreadProcessId = _user32
      .lookupFunction<_GetWindowThreadProcessIdNative, _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
  static final _GetWindowLongPtrWDart _getWindowLongPtr = _user32
      .lookupFunction<_GetWindowLongPtrWNative, _GetWindowLongPtrWDart>('GetWindowLongPtrW');
  static final _SetWindowLongPtrWDart _setWindowLongPtr = _user32
      .lookupFunction<_SetWindowLongPtrWNative, _SetWindowLongPtrWDart>('SetWindowLongPtrW');
  static final _SetWindowPosDart _setWindowPos = _user32.lookupFunction<_SetWindowPosNative, _SetWindowPosDart>(
    'SetWindowPos',
  );
  static final _GetWindowPlacementDart _getWindowPlacement = _user32
      .lookupFunction<_GetWindowPlacementNative, _GetWindowPlacementDart>('GetWindowPlacement');
  static final _SetWindowPlacementDart _setWindowPlacement = _user32
      .lookupFunction<_SetWindowPlacementNative, _SetWindowPlacementDart>('SetWindowPlacement');
  static final _MonitorFromWindowDart _monitorFromWindow = _user32
      .lookupFunction<_MonitorFromWindowNative, _MonitorFromWindowDart>('MonitorFromWindow');
  static final _GetMonitorInfoWDart _getMonitorInfo = _user32
      .lookupFunction<_GetMonitorInfoWNative, _GetMonitorInfoWDart>('GetMonitorInfoW');
  static final _IsZoomedDart _isZoomed = _user32.lookupFunction<_IsZoomedNative, _IsZoomedDart>('IsZoomed');
  static final _GetWindowRectDart _getWindowRect = _user32.lookupFunction<_GetWindowRectNative, _GetWindowRectDart>(
    'GetWindowRect',
  );
  static final _SendMessageWDart _sendMessage = _user32.lookupFunction<_SendMessageWNative, _SendMessageWDart>(
    'SendMessageW',
  );

  /// The runner window of this process, or null when not found.
  ///
  /// Flutter's runner registers a well-known window class, so the window is
  /// found by class and verified to belong to this process; multi-instance
  /// hosts get the top-most window of *their own* process, never another
  /// instance's.
  static int? mainWindowHandle() {
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    try {
      final currentPid = _getCurrentProcessId();
      final pidPtr = calloc<_Dword>();
      try {
        var hwnd = _findWindow(className, nullptr);
        while (hwnd != 0) {
          _getWindowThreadProcessId(hwnd, pidPtr);
          if (pidPtr.value == currentPid) {
            return hwnd;
          }
          hwnd = _findWindowEx(0, hwnd, className, nullptr);
        }
        return null;
      } finally {
        calloc.free(pidPtr);
      }
    } finally {
      calloc.free(className);
    }
  }

  /// Captures everything needed to restore the window later.
  static Win32WindowSnapshot? capture(int hwnd) {
    if (hwnd == 0) return null;
    final placementPtr = calloc<_WindowPlacement>();
    try {
      final placement = placementPtr.ref..length = sizeOf<_WindowPlacement>();
      if (_getWindowPlacement(hwnd, placementPtr) == 0) {
        return null;
      }

      return Win32WindowSnapshot._(
        hwnd,
        _getWindowLongPtr(hwnd, _gwlStyle),
        _getWindowLongPtr(hwnd, _gwlExStyle),
        _isZoomed(hwnd) != 0,
        [
          placement.flags,
          placement.showCmd,
          placement.ptMinPosition.x,
          placement.ptMinPosition.y,
          placement.ptMaxPosition.x,
          placement.ptMaxPosition.y,
          placement.rcNormalPosition.left,
          placement.rcNormalPosition.top,
          placement.rcNormalPosition.right,
          placement.rcNormalPosition.bottom,
        ],
      );
    } finally {
      calloc.free(placementPtr);
    }
  }

  /// The window's current bounds, or null when unavailable.
  static Rect? bounds(int hwnd) {
    if (hwnd == 0) return null;
    final rectPtr = calloc<_Rect>();
    try {
      if (_getWindowRect(hwnd, rectPtr) == 0) {
        return null;
      }
      final r = rectPtr.ref;
      return Rect.fromLTWH(
        r.left.toDouble(),
        r.top.toDouble(),
        (r.right - r.left).toDouble(),
        (r.bottom - r.top).toDouble(),
      );
    } finally {
      calloc.free(rectPtr);
    }
  }

  /// Whether the window currently carries the top-most bit.
  static bool isTopmost(int hwnd) {
    if (hwnd == 0) return false;
    return (_getWindowLongPtr(hwnd, _gwlExStyle) & _wsExTopmost) != 0;
  }

  /// Whether the window is hidden from the taskbar and Alt-Tab.
  static bool isSkipTaskbar(int hwnd) {
    if (hwnd == 0) return false;
    return (_getWindowLongPtr(hwnd, _gwlExStyle) & _wsExToolwindow) != 0;
  }

  /// Toggles the tool-window bit: the same `WS_EX_TOOLWINDOW` switch the
  /// `window_manager` plugin performs in its `set_skip_taskbar.cpp`, done
  /// here directly so hosts whose plugin is on its frameless fast path still
  /// get the change. A frame recalculation follows so the ex-style takes
  /// visible effect.
  static bool setSkipTaskbar(int hwnd, {required bool skip}) {
    if (hwnd == 0) return false;
    final exStyle = _getWindowLongPtr(hwnd, _gwlExStyle);
    final updated = skip ? (exStyle | _wsExToolwindow) : (exStyle & ~_wsExToolwindow);
    _setWindowLongPtr(hwnd, _gwlExStyle, updated);
    return _forceRelayout(hwnd);
  }

  /// Whether the window carries the sizing frame (user-resizable edges).
  static bool isResizable(int hwnd) {
    if (hwnd == 0) return false;
    return (_getWindowLongPtr(hwnd, _gwlStyle) & _wsThickframe) != 0;
  }

  /// Toggles the sizing frame: a compact picture-in-picture window drops
  /// `WS_THICKFRAME` so the small window cannot be stretched by its edges.
  static bool setResizable(int hwnd, {required bool resizable}) {
    if (hwnd == 0) return false;
    final style = _getWindowLongPtr(hwnd, _gwlStyle);
    final updated = resizable ? (style | _wsThickframe) : (style & ~_wsThickframe);
    _setWindowLongPtr(hwnd, _gwlStyle, updated);
    return _forceRelayout(hwnd);
  }

  /// The window's title text, or '' when unavailable.
  static String windowTitle(int hwnd) {
    if (hwnd == 0) return '';
    final length = _sendMessage(hwnd, _wmGettextlength, 0, 0);
    if (length <= 0) return '';
    final buffer = calloc<Uint16>(length + 1);
    try {
      _sendMessage(hwnd, _wmGettext, length + 1, buffer.address);
      return Pointer<Utf16>.fromAddress(buffer.address).toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  /// Begins a native drag of the window: releases the mouse capture Flutter
  /// holds and enters the caption drag loop via `WM_NCLBUTTONDOWN(HTCAPTION)`.
  /// Works on any window regardless of its style bits — the compact
  /// picture-in-picture window has neither a title bar nor `WS_THICKFRAME`,
  /// so a surface-initiated drag is the only way to move it.
  ///
  /// The `SendMessage` is synchronous and returns when the drag loop ends;
  /// the loop pumps messages, so Flutter keeps rendering while it runs.
  static bool startDragging(int hwnd) {
    if (hwnd == 0) return false;
    _releaseCapture();
    return _sendMessage(hwnd, _wmNclbuttondown, _htcaption, 0) != 0;
  }

  /// Requests rounded window corners (Windows 11 `DWMWA_WINDOW_CORNER_PREFERENCE`).
  ///
  /// The compact picture-in-picture window reads as a floating card only when
  /// its corners are rounded; a freshly shrunk frameless window comes out
  /// square. Older systems ignore the attribute (the call fails silently),
  /// which simply keeps the square window they can render.
  static bool setRoundedCorners(int hwnd, {required bool round}) {
    if (hwnd == 0) return false;
    final setter = _dwmSetWindowAttribute;
    if (setter == null) return false;
    final preference = calloc<_Dword>();
    try {
      preference.value = round ? _dwmwcpRound : _dwmwcpDefault;
      return setter(hwnd, _dwmwaWindowCornerPreference, preference, sizeOf<_Dword>()) == 0;
    } finally {
      calloc.free(preference);
    }
  }

  /// Moves the window into or out of the top-most band without touching its
  /// bounds: the z-order toggle a compact picture-in-picture window needs
  /// when the user flips the always-on-top setting mid-session.
  static bool setTopmost(int hwnd, {required bool topmost}) {
    if (hwnd == 0) return false;
    return _setWindowPos(
          hwnd,
          topmost ? _hwndTopmost : _hwndNotopmost,
          0,
          0,
          0,
          0,
          _swpNoSize | _swpNoMove | _swpNoActivate | _swpFrameChanged,
        ) !=
        0;
  }

  /// Moves the window to [rect] in one atomic call.
  ///
  /// No style bits are touched: the host's chrome state (a custom-drawn title
  /// bar) is exactly what it already is. `SWP_FRAMECHANGED` keeps the frame
  /// state and the bounds consistent in a single update.
  static bool applyBounds(int hwnd, Rect rect, {required bool topmost}) {
    if (hwnd == 0) return false;
    return _setWindowPos(
          hwnd,
          topmost ? _hwndTopmost : _hwndNoZorderChange,
          rect.left.round(),
          rect.top.round(),
          rect.width.round(),
          rect.height.round(),
          _swpShowWindow | _swpFrameChanged,
        ) !=
        0;
  }

  /// Restores a snapshot taken by [capture].
  ///
  /// A trailing no-op `SetWindowPos` forces Flutter to re-layout — after a
  /// frame change the layout is not always correct otherwise.
  static bool restoreSnapshot(Win32WindowSnapshot snapshot) {
    final hwnd = snapshot.hwnd;
    if (hwnd == 0) return false;
    final placementPtr = calloc<_WindowPlacement>();
    try {
      final p = placementPtr.ref;
      final v = snapshot._placement;
      p
        ..length = sizeOf<_WindowPlacement>()
        ..flags = v[0]
        ..showCmd = v[1]
        ..ptMinPosition.x = v[2]
        ..ptMinPosition.y = v[3]
        ..ptMaxPosition.x = v[4]
        ..ptMaxPosition.y = v[5]
        ..rcNormalPosition.left = v[6]
        ..rcNormalPosition.top = v[7]
        ..rcNormalPosition.right = v[8]
        ..rcNormalPosition.bottom = v[9];
      _setWindowPlacement(hwnd, placementPtr);
    } finally {
      calloc.free(placementPtr);
    }

    _setWindowLongPtr(hwnd, _gwlExStyle, snapshot._exStyle);
    _setWindowLongPtr(hwnd, _gwlStyle, snapshot._style);
    return _forceRelayout(hwnd);
  }

  /// Fullscreen in the `fullscreen_window` sequence.
  ///
  /// Entering: strip the caption/thickframe bits, then fill the monitor the
  /// window is on, top-most. Leaving: restore the command, the styles and the
  /// captured placement, then force a re-layout.
  static bool setScreenFullscreen(int hwnd, {required bool fullscreen, Win32WindowSnapshot? snapshot}) {
    if (hwnd == 0) return false;

    if (fullscreen) {
      if (snapshot != null) {
        _setWindowLongPtr(hwnd, _gwlStyle, snapshot._style & ~(_wsCaption | _wsThickframe | _wsMaximize));
        _setWindowLongPtr(
          hwnd,
          _gwlExStyle,
          (snapshot._exStyle | _wsExTopmost) &
              ~(_wsExDlgModalFrame | _wsExWindowEdge | _wsExClientEdge | _wsExStaticEdge),
        );
      }
      final monitor = _monitorFromWindow(hwnd, _monitorDefaultToNearest);
      final infoPtr = calloc<_MonitorInfo>();
      try {
        final info = infoPtr.ref..cbSize = sizeOf<_MonitorInfo>();
        if (monitor == 0 || _getMonitorInfo(monitor, infoPtr) == 0) {
          return false;
        }
        return _setWindowPos(
              hwnd,
              _hwndTopmost,
              info.rcMonitor.left,
              info.rcMonitor.top,
              info.rcMonitor.right - info.rcMonitor.left,
              info.rcMonitor.bottom - info.rcMonitor.top,
              _swpShowWindow | _swpFrameChanged,
            ) !=
            0;
      } finally {
        calloc.free(infoPtr);
      }
    }

    if (snapshot != null) {
      if (!snapshot._maximized) {
        _sendMessage(hwnd, _wmSyscommand, _scRestore, 0);
      }
      return restoreSnapshot(snapshot);
    }
    return _forceRelayout(hwnd);
  }

  static bool _forceRelayout(int hwnd) {
    final rectPtr = calloc<_Rect>();
    try {
      if (_getWindowRect(hwnd, rectPtr) == 0) return false;
      final r = rectPtr.ref;
      return _setWindowPos(
            hwnd,
            0,
            r.left,
            r.top,
            r.right - r.left,
            r.bottom - r.top,
            _swpNoZorder | _swpNoActivate | _swpFrameChanged,
          ) !=
          0;
    } finally {
      calloc.free(rectPtr);
    }
  }
}
