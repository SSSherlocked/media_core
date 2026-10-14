import 'package:equatable/equatable.dart';
import 'package:media_core/casting/media_cast_backend.dart' show MediaCastBackend;

/// A discovered render device a cast can be sent to.
///
/// [CastDevice] is protocol-neutral on purpose: a DLNA DMR, a Chromecast
/// and a future AirPlay receiver all answer to the same shape — an
/// identity, a human name, and an opaque [serviceEndpoints] map the
/// backend that discovered the device understands. Nothing above the
/// [MediaCastBackend] boundary inspects those endpoints, which is what
/// lets a UI list devices without importing a single protocol type.
///
/// Responsibilities:
///
/// - identify a render target for the controller and the UI
///
/// It does not:
///
/// - carry transport state
/// - expose protocol URLs to callers
///
/// Those belong to:
///
/// - CastController
/// - the backend that produced the device
final class CastDevice extends Equatable {
  /// Creates a discovered device.
  const CastDevice({
    required this.id,
    required this.name,
    required this.backendId,
    this.typeName,
    this.manufacturer,
    this.modelName,
    this.serviceEndpoints = const <String, String>{},
    this.attributes = const <String, Object?>{},
  });

  /// Stable identity within one discovery session, normally the
  /// protocol's own UDN/device id.
  final String id;

  /// The friendly name the device advertises; what a picker shows.
  final String name;

  /// Which backend discovered this device (`dlna`, `cast`, ...).
  ///
  /// Carried on the device because a controller may hold several
  /// backends at once and commands must go back to the one that
  /// found the target.
  final String backendId;

  /// Protocol type name (a DLNA `urn:schemas-upnp-org:device:...`),
  /// when the device reports one.
  final String? typeName;

  /// Advertised manufacturer, when present.
  final String? manufacturer;

  /// Advertised model name, when present.
  final String? modelName;

  /// Control URLs or equivalent handles, keyed by service id.
  ///
  /// The map is opaque above the backend: keys and values mean
  /// whatever the discovering protocol says they mean, and the
  /// controller never reads them.
  final Map<String, String> serviceEndpoints;

  /// Extra device facts (icons, features); opaque to media_core.
  final Map<String, Object?> attributes;

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    backendId,
    typeName,
    manufacturer,
    modelName,
    serviceEndpoints,
    attributes,
  ];
}
