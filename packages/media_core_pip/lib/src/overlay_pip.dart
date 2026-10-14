import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Thin seam over the static `flutter_overlay_window` API, so the rest of the
/// package can be driven by tests and a host can swap the backend.
abstract interface class OverlayWindowApi {
  /// Whether the viewer has granted the draw-over-other-apps permission.
  Future<bool> isPermissionGranted();

  /// Opens the system settings page for the permission; completes when the
  /// viewer comes back, granted or not.
  Future<bool?> requestPermission();

  /// Opens the overlay window. [width] and [height] are physical pixels — the
  /// plugin feeds them straight into `WindowManager.LayoutParams`.
  Future<void> showOverlay({
    required int width,
    required int height,
    required bool enableDrag,
    required String title,
  });

  /// Whether the overlay window is currently on screen.
  Future<bool> isActive();

  /// Closes the overlay window.
  Future<bool?> closeOverlay();

  /// Sends a message to the other engine.
  Future<void> shareData(Object data);

  /// Messages from the other engine. Reading the getter installs the
  /// channel handler (the plugin's `overlayListener`).
  Stream<Object?> get messages;
}

/// The production seam, over the plugin's static methods.
final class MethodChannelOverlayWindow implements OverlayWindowApi {
  /// Stateless: every call goes straight to the plugin's static methods, so
  /// one instance is as good as any other and the seam can be a const.
  const MethodChannelOverlayWindow();

  @override
  Future<bool> isPermissionGranted() => FlutterOverlayWindow.isPermissionGranted();

  @override
  Future<bool?> requestPermission() => FlutterOverlayWindow.requestPermission();

  @override
  Future<void> showOverlay({
    required int width,
    required int height,
    required bool enableDrag,
    required String title,
  }) {
    return FlutterOverlayWindow.showOverlay(
      width: width,
      height: height,
      // A video overlay starts in a corner and can be dragged anywhere; after
      // a drag it snaps to the nearer screen edge, like a chat head.
      alignment: OverlayAlignment.bottomRight,
      enableDrag: enableDrag,
      positionGravity: PositionGravity.auto,
      // The default flag keeps the window touchable (its close button works)
      // without stealing key input from whatever the viewer is doing
      // underneath.
      overlayTitle: title,
    );
  }

  @override
  Future<bool> isActive() => FlutterOverlayWindow.isActive();

  @override
  Future<bool?> closeOverlay() => FlutterOverlayWindow.closeOverlay();

  @override
  Future<void> shareData(Object data) => FlutterOverlayWindow.shareData(data);

  @override
  Stream<Object?> get messages => FlutterOverlayWindow.overlayListener;
}

/// The message types flowing between the app engine and the overlay engine.
///
/// The overlay runs in a second Flutter engine with a fresh isolate: it knows
/// nothing the main app did not tell it. Everything it needs travels as a map
/// over the plugin's messenger channel.
final class OverlayPipMessages {
  const OverlayPipMessages._(this.map);

  /// Parses one messenger payload; null when it is not one of ours.
  static OverlayPipMessages? parse(Object? message) {
    if (message is Map && message['type'] is String) {
      return OverlayPipMessages._(Map<String, Object?>.from(message));
    }
    return null;
  }

  /// Builds the "here is what to play" payload.
  static Map<String, Object?> media({required String url, Duration? position, String? title}) {
    return <String, Object?>{
      'type': 'media',
      'url': url,
      'positionMs': position?.inMilliseconds,
      'title': title,
    };
  }

  /// Builds the overlay engine's "I am listening" handshake.
  static Map<String, Object?> ready() => <String, Object?>{'type': 'ready'};

  /// Builds the viewer-tapped-close event, carrying the position to resume
  /// from when the host player reported one.
  static Map<String, Object?> close({Duration? position}) {
    return <String, Object?>{
      'type': 'close',
      'positionMs': position?.inMilliseconds,
    };
  }

  /// One of `media`, `ready`, `close`.
  String get type => map['type']! as String;

  /// The URL the overlay engine should open, when [type] is `media`.
  String? get url => map['url'] as String?;

  /// Where the source was when the handoff was asked for.
  Duration? get position {
    final ms = map['positionMs'];
    return ms is int ? Duration(milliseconds: ms) : null;
  }

  /// The raw payload, as it crossed the channel. A host-side widget that
  /// wants a field the typed getters do not expose reads it here.
  final Map<String, Object?> map;
}

/// App-engine side of the overlay link.
///
/// The overlay engine boots after [OverlayWindowApi.showOverlay], so a payload
/// sent with the show request can arrive before its listener exists. The
/// handshake below closes that race: the overlay reports `ready` once it is
/// listening, and the latest payload is replayed.
final class OverlayPipLink {
  /// Builds the link over [window].
  OverlayPipLink(this.window);

  /// Where payloads and events travel.
  final OverlayWindowApi window;

  StreamSubscription<Object?>? _subscription;
  Map<String, Object?>? _pendingPayload;

  /// Fires for every overlay event except the ready handshake — currently
  /// only `close`.
  void Function(OverlayPipMessages event)? onEvent;

  /// Where the overlay said it was when the viewer closed it, for the
  /// handback. Null until a close event carried one.
  Duration? get lastClosedPosition => _lastClosedPosition;
  Duration? _lastClosedPosition;

  /// Starts listening and sends the first payload.
  Future<void> open(Map<String, Object?> payload) async {
    _pendingPayload = payload;
    await _subscription?.cancel();
    _subscription = window.messages.listen(_handle);
    await window.shareData(payload);
  }

  void _handle(Object? message) {
    final event = OverlayPipMessages.parse(message);
    if (event == null) return;
    switch (event.type) {
      case 'ready':
        // The overlay engine just mounted its listener; it missed anything
        // sent earlier, so replay the payload it exists to render.
        final payload = _pendingPayload;
        if (payload != null) unawaited(window.shareData(payload));
      case 'close':
        _lastClosedPosition = event.position;
        onEvent?.call(event);
      default:
        onEvent?.call(event);
    }
  }

  /// Stops listening and forgets the pending payload.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _pendingPayload = null;
  }
}

/// Overlay-engine side of the link. One per overlay engine.
///
/// Exposes what the app sent as a [ValueListenable] so the host's overlay
/// widget tree can rebuild on it, and carries the close tap back before the
/// window goes away.
final class OverlayPipSession {
  OverlayPipSession._() {
    FlutterOverlayWindow.overlayListener.listen((message) {
      final event = OverlayPipMessages.parse(message);
      if (event == null || event.type != 'media') return;
      _payload.value = event;
      // The app may have sent its payload before this engine finished booting;
      // answering the handshake makes it replay.
      unawaited(FlutterOverlayWindow.shareData(OverlayPipMessages.ready()));
    });
  }

  /// The singleton of this overlay engine.
  static final OverlayPipSession instance = OverlayPipSession._();

  final ValueNotifier<OverlayPipMessages?> _payload = ValueNotifier<OverlayPipMessages?>(null);

  /// What the window should show; null until the app sent it.
  ValueListenable<OverlayPipMessages?> get payload => _payload;

  /// Closes the overlay, telling the app first so it can resume its own
  /// playback from [position].
  static Future<void> close(Duration? position) async {
    await FlutterOverlayWindow.shareData(OverlayPipMessages.close(position: position));
    await FlutterOverlayWindow.closeOverlay();
  }
}

/// Runs the overlay engine. Call from the host's `overlayMain` entrypoint —
/// the function Android looks up when the overlay engine boots:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void overlayMain() => overlayPipMain(builder: (context) => MyVideoPage());
/// ```
///
/// [builder] reads `OverlayPipSession.instance.payload` for the URL and the
/// position to open the player with. Without a builder a bare placeholder
/// renders — enough to smoke-test the wiring, not a player.
Future<void> overlayPipMain({WidgetBuilder? builder}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = OverlayPipSession.instance;
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _OverlayPipHome(session: session, builder: builder),
  ));
}

class _OverlayPipHome extends StatelessWidget {
  const _OverlayPipHome({required this.session, this.builder});

  final OverlayPipSession session;
  final WidgetBuilder? builder;

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    if (builder != null) {
      return Builder(builder: builder);
    }
    return ValueListenableBuilder<OverlayPipMessages?>(
      valueListenable: session.payload,
      builder: (context, payload, _) => _OverlayPipPlaceholder(payload: payload),
    );
  }
}

/// What shows when the host installed no overlay builder: the wiring, minus
/// the picture. It names what is missing so a black window never looks like a
/// playback bug.
class _OverlayPipPlaceholder extends StatelessWidget {
  const _OverlayPipPlaceholder({this.payload});

  final OverlayPipMessages? payload;

  @override
  Widget build(BuildContext context) {
    final url = payload?.url;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No overlay builder installed',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (url != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
                child: Text(
                  url,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => OverlayPipSession.close(null),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
