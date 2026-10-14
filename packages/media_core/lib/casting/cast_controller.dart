import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:media_core/casting/cast_device.dart';
import 'package:media_core/casting/cast_media.dart';
import 'package:media_core/casting/cast_transport.dart';
import 'package:media_core/casting/media_cast_backend.dart';

/// The app-facing cast session over a [MediaCastBackend].
///
/// [CastController] turns "a protocol that answers commands" into
/// "a piece of UI state": which devices are present, which one is
/// picked, what is loaded, where its playhead is. It owns exactly the
/// glue a cast needs and nothing a device does:
///
/// - **presence** — devices arrive and leave on the backend stream;
///   a lost device clears an active session instead of leaving a
///   progress bar counting up on a TV that is no longer there;
/// - **the playhead tick** — position is polled on an interval
///   ([positionInterval], default 2s) because DLNA eventing needs a
///   GENA server a Flutter app should not have to run; when one poll
///   fails the previous position is kept and the state marked
///   [CastTransportState.unknown], so a transient hiccup grays the ring out rather than
///   snapping it to zero;
/// - **command honesty** — every command awaits, propagates
///   [CastException], and re-reads state after success, because a
///   receiver that accepted SetURI can still refuse to play.
///
/// Responsibilities:
///
/// - expose device/session state as listenables for a picker and a bar
/// - poll the receiver playhead
///
/// It does not:
///
/// - encode protocols (the backend)
/// - keep the local player and the cast in sync (a host that wants
///   handoff composes the two itself)
/// - persist the chosen device
///
/// Those belong to:
///
/// - MediaCastBackend
/// - the host
/// - the host
final class CastController extends ChangeNotifier {
  /// Creates a controller over [backend].
  ///
  /// [positionInterval] overrides how often the playhead is polled
  /// during playback; a backend with real push eventing can pass
  /// [Duration.zero] to disable polling and drive [refresh] itself.
  CastController({required this.backend, this.positionInterval = const Duration(seconds: 2)}) {
    _events = backend.events.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        _fault(CastFault(deviceId: _device?.id, message: 'cast event stream failed', error: error));
      },
    );
  }

  /// The protocol implementation being driven.
  final MediaCastBackend backend;

  /// How often the playhead is polled while playing.
  final Duration positionInterval;

  late final StreamSubscription<CastEvent> _events;
  Timer? _ticker;

  /// Whether a position poll from the ticker is still waiting on the device.
  ///
  /// `backend.position` is a network round trip to a renderer that may be slow
  /// or wedged; an unguarded periodic ticker would stack those requests
  /// indefinitely and let a late answer overwrite the position a newer one
  /// already read.
  bool _refreshInFlight = false;

  final List<CastDevice> _devices = <CastDevice>[];
  CastDevice? _device;
  CastMedia? _media;
  CastPosition _position = const CastPosition.unknown();
  CastTransportState _state = CastTransportState.noMedia;
  bool _disposed = false;

  /// Devices currently present, in discovery order.
  List<CastDevice> get devices => List<CastDevice>.unmodifiable(_devices);

  /// The device a session is active on, if any.
  CastDevice? get device => _device;

  /// The media loaded on [device], if any.
  CastMedia? get media => _media;

  /// Latest playhead reading.
  CastPosition get position => _position;

  /// Latest transport state.
  CastTransportState get transportState => _state;

  /// Whether a session is active.
  bool get isCasting => _device != null && _media != null;

  /// Sends [media] to [target] and starts playback.
  ///
  /// Sets the device first: a UI tapping a new TV while another is
  /// already casting is switching devices, and the previous device's
  /// session is stopped so two receivers never keep playing the same
  /// item at once.
  Future<void> cast(CastDevice target, CastMedia media) async {
    _ensureActive();

    if (_device != null && _device!.id != target.id) {
      await _stopQuietly(_device!);
    }
    _device = target;
    _media = media;

    await backend.setMedia(target, media);
    _state = CastTransportState.stopped;
    notifyListeners();

    await backend.play(target);
    _state = CastTransportState.playing;
    notifyListeners();

    await refresh();
    _startTicker();
  }

  /// Pauses the receiver.
  Future<void> pause() async {
    _ensureActive();
    final target = _requireDevice();
    await backend.pause(target);
    _state = CastTransportState.paused;
    notifyListeners();
  }

  /// Resumes the receiver.
  Future<void> resume() async {
    _ensureActive();
    final target = _requireDevice();
    await backend.play(target);
    _state = CastTransportState.playing;
    _startTicker();
    notifyListeners();
  }

  /// Seeks on the receiver and reflects the new position immediately.
  Future<void> seek(Duration position) async {
    _ensureActive();
    final target = _requireDevice();
    await backend.seek(target, position);
    _position = CastPosition(position: position, duration: _position.duration, transportState: _state);
    notifyListeners();
    unawaited(refresh());
  }

  /// Sets receiver volume, 0..100.
  Future<void> setVolume(int percent) async {
    _ensureActive();
    await backend.setVolume(_requireDevice(), percent.clamp(0, 100));
  }

  /// Stops casting and releases the session. The device stays in
  /// [devices]; only the session ends.
  Future<void> stopCasting() async {
    _ensureActive();
    final target = _device;
    if (target == null) {
      return;
    }
    await _stopQuietly(target);
    _device = null;
    _media = null;
    _state = CastTransportState.noMedia;
    _position = const CastPosition.unknown();
    _stopTicker();
    notifyListeners();
  }

  /// Re-reads position and transport from the receiver.
  ///
  /// A failure marks the reading [CastTransportState.unknown] and
  /// keeps the last position: the UI must be able to tell "the TV
  /// said it stopped" from "the TV did not answer", and overwriting
  /// the last good position with zero is how a progress bar lies.
  Future<void> refresh() async {
    final target = _device;
    if (target == null) {
      return;
    }
    try {
      final read = await backend.position(target);
      _position = read;
      _state = read.transportState == CastTransportState.unknown ? _state : read.transportState;
    } on CastException {
      _state = CastTransportState.unknown;
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Releases the controller; the backend survives for other users.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopTicker();
    await _events.cancel();
    super.dispose();
  }

  void _onEvent(CastEvent event) {
    switch (event) {
      case DeviceFound(:final device):
        _upsertDevice(device);
      case DeviceLost(:final deviceId):
        _removeDevice(deviceId);
      case TransportStateChanged(:final state):
        if (_device?.id == event.deviceId && state != _state) {
          _state = state;
          notifyListeners();
        }
      case CastFault():
        _fault(event);
    }
  }

  void _fault(CastFault fault) {
    if (_device != null && fault.deviceId == _device!.id) {
      _state = CastTransportState.unknown;
      notifyListeners();
    }
  }

  void _upsertDevice(CastDevice device) {
    final index = _devices.indexWhere((existing) => existing.id == device.id);
    if (index < 0) {
      _devices.add(device);
    } else {
      _devices[index] = device;
    }
    notifyListeners();
  }

  void _removeDevice(String deviceId) {
    final index = _devices.indexWhere((existing) => existing.id == deviceId);
    if (index < 0) {
      return;
    }
    _devices.removeAt(index);
    // A lost device ends any session on it: a control bar driving a
    // TV that left the network would otherwise keep polling forever
    // and show a playhead advancing through nothing.
    if (_device?.id == deviceId) {
      _device = null;
      _media = null;
      _state = CastTransportState.noMedia;
      _position = const CastPosition.unknown();
      _stopTicker();
    }
    notifyListeners();
  }

  Future<void> _stopQuietly(CastDevice target) async {
    try {
      await backend.stop(target);
    } on CastException {
      // A device already gone answers nothing; the session is being
      // left either way, and this is the user-visible "switch device"
      // path, not a place to surface a second error.
    }
  }

  void _startTicker() {
    _stopTicker();
    if (positionInterval <= Duration.zero) {
      return;
    }
    _ticker = Timer.periodic(positionInterval, (_) {
      if (_state == CastTransportState.playing && !_refreshInFlight) {
        _refreshInFlight = true;
        unawaited(refresh().whenComplete(() => _refreshInFlight = false));
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  CastDevice _requireDevice() {
    final target = _device;
    if (target == null) {
      throw const CastException('No cast device selected.');
    }
    return target;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('CastController has been disposed.');
    }
  }
}
