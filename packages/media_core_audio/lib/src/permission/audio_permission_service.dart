import 'dart:async';

import 'package:flutter/services.dart';

import 'package:media_core_audio/src/permission/audio_permission.dart';

/// Asks the platform for the runtime permissions the music module needs.
///
/// ```dart
/// final permissions = AudioPermissionService();
///
/// if (!await permissions.isGranted(AudioPermission.notifications)) {
///   await permissions.request(AudioPermission.notifications);
/// }
///
/// // Show the overlay only once it can actually be drawn.
/// if (await permissions.request(AudioPermission.desktopLyricOverlay)) {
///   await desktopLyric.show();
/// }
/// ```
///
/// The service is a thin, honest wrapper: it reports what the platform says
/// and never pretends a permission exists. On a platform where a permission is
/// meaningless (no notification permission outside Android 13+, no overlay
/// authorization outside Android) both [isGranted] and [request] answer `true`,
/// so a host can ask unconditionally.
final class AudioPermissionService {
  /// Creates a service.
  AudioPermissionService({AudioPermissionTransport? transport})
    : _transport = transport ?? MethodChannelAudioPermissionTransport();

  final AudioPermissionTransport _transport;

  /// Whether every one of the module's live permissions is granted.
  ///
  /// `AudioPermission.notifications` and `AudioPermission.mediaLibrary` are only
  /// requested when the host uses the feature, so they are not part of this check.
  Future<bool> get isReady => isGranted(AudioPermission.desktopLyricOverlay);

  /// Whether [permission] is currently granted.
  Future<bool> isGranted(AudioPermission permission) => _transport.isGranted(permission);

  /// Requests [permission], resolving with the result.
  ///
  /// For [AudioPermission.desktopLyricOverlay] this opens the system settings
  /// screen and resolves once the user returns — the overlay case cannot be
  /// answered by a dialog, so the future deliberately spans the round trip
  /// instead of returning "false, try again later".
  Future<bool> request(AudioPermission permission) => _transport.request(permission);

  /// Requests every permission in [permissions], in order, stopping at the
  /// first refusal.
  ///
  /// Stopping matters on Android: each request shows UI, and a user who
  /// declined the first one does not want three more dialogs.
  Future<Map<AudioPermission, bool>> requestAll(Iterable<AudioPermission> permissions) async {
    final results = <AudioPermission, bool>{};

    for (final permission in permissions) {
      final granted = await request(permission);

      results[permission] = granted;

      if (!granted) {
        break;
      }
    }

    return results;
  }
}

/// Platform transport behind [AudioPermissionService].
abstract interface class AudioPermissionTransport {
  /// Whether [permission] is granted right now.
  Future<bool> isGranted(AudioPermission permission);

  /// Requests [permission].
  Future<bool> request(AudioPermission permission);
}

/// [AudioPermissionTransport] over a `MethodChannel` to the host plugin.
///
/// Protocol — channel `media_core_audio/permissions`:
///
/// | method | arguments | result |
/// |---|---|---|
/// | `isGranted` | `{permission: <AudioPermission.name>}` | `bool` |
/// | `request` | `{permission: <AudioPermission.name>}` | `bool` (after the round trip) |
///
/// A platform whose plugin does not implement the channel (the desktop ones
/// need no permissions at all) answers `true` for everything.
final class MethodChannelAudioPermissionTransport implements AudioPermissionTransport {
  /// Creates a transport.
  MethodChannelAudioPermissionTransport({MethodChannel? channel, this.channelName = defaultChannelName})
    : _channel = channel ?? const MethodChannel(defaultChannelName);

  /// Default channel name.
  static const String defaultChannelName = 'media_core_audio/permissions';

  /// Channel this transport talks on.
  final String channelName;

  final MethodChannel _channel;
  final Map<AudioPermission, bool> _cache = <AudioPermission, bool>{};

  @override
  Future<bool> isGranted(AudioPermission permission) async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('isGranted', <String, Object?>{'permission': permission.name}) ?? false;

      _cache[permission] = granted;

      return granted;
    } on MissingPluginException {
      // No permission concept on this platform for this plugin.
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> request(AudioPermission permission) async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('request', <String, Object?>{'permission': permission.name}) ?? false;

      _cache[permission] = granted;

      return granted;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Last known value, when one was already read or requested.
  bool? cached(AudioPermission permission) => _cache[permission];
}

/// A transport for platforms and tests without permission plumbing: everything
/// is granted, which is the truth on desktop.
final class NoopAudioPermissionTransport implements AudioPermissionTransport {
  /// Creates the transport.
  NoopAudioPermissionTransport();

  @override
  Future<bool> isGranted(AudioPermission permission) async => true;

  @override
  Future<bool> request(AudioPermission permission) async => true;
}
