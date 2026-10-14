import 'package:media_core_cast_dlna/media_core_cast_dlna.dart' show DlnaCastBackend, SsdpDiscovery;
import 'package:media_core_cast_dlna/src/ssdp_message.dart';

/// The discovery feed a [DlnaCastBackend] consumes.
///
/// [SsdpDiscovery] is the production implementation; tests drive a
/// scripted one, because a CI box has neither a multicast route nor a
/// TV to answer it. Keeping the seam at the message stream (not at the
/// socket) is also what lets a future backend reuse discovery over
/// Bluetooth or mDNS announcements without the cast logic noticing.
abstract interface class SsdpSource {
  /// Parsed SSDP messages, alive, byebye and expiry alike.
  Stream<SsdpMessage> get messages;

  /// Begins listening and searching. Idempotent.
  Future<void> start();

  /// Stops and releases everything.
  Future<void> stop();
}
