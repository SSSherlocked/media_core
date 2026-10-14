import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_factory.dart';

/// Registry of available player adapters.
///
/// [PlayerAdapterRegistry] stores metadata about
/// available playback backends.
///
/// Responsibilities:
///
/// - register adapters
/// - lookup adapters
/// - expose capabilities
///
/// It does not:
///
/// - create adapter instances
/// - select best adapter
/// - control playback
///
/// Those belong to:
///
/// - PlayerAdapterFactory
/// - BackendSelector
/// - PlayerAdapter
final class PlayerAdapterRegistry {
  /// Creates registry.
  PlayerAdapterRegistry();

  final Map<String, PlayerAdapterRegistration> _entries = {};

  /// Registers an adapter.
  ///
  /// Throws [ArgumentError] for a blank [PlayerAdapterRegistration.id]:
  /// an empty id is ambiguous by nature — every factory would claim it —
  /// so it is never allowed into the registry instead of being resolved
  /// by consultation order.
  void register(PlayerAdapterRegistration registration) {
    final id = registration.id;

    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'registration.id', 'Backend id must not be blank.');
    }

    _entries[id] = registration;
  }

  /// Removes adapter registration.
  void unregister(String id) {
    _entries.remove(id);
  }

  /// Gets registration.
  PlayerAdapterRegistration? get(String id) {
    return _entries[id];
  }

  /// Whether adapter exists.
  bool contains(String id) {
    return _entries.containsKey(id);
  }

  /// Returns all registrations.
  List<PlayerAdapterRegistration> get registrations {
    return List.unmodifiable(_entries.values);
  }

  /// Returns all adapter ids.
  List<String> get ids {
    return List.unmodifiable(_entries.keys);
  }

  /// Number of registered adapters.
  int get length {
    return _entries.length;
  }

  /// Clears registry.
  void clear() {
    _entries.clear();
  }
}

/// Adapter registration information.
///
/// Contains everything needed by selector
/// and factory.
///
/// It does not create the adapter itself.
final class PlayerAdapterRegistration {
  /// Creates registration.
  const PlayerAdapterRegistration({
    required this.id,
    required this.factory,
    required this.capabilities,
    this.priority = 0,
    this.enabled = true,
  });

  /// Adapter identifier.
  ///
  /// Example:
  ///
  /// - media_kit
  /// - native
  /// - ffmpeg
  final String id;

  /// Adapter factory.
  final PlayerAdapterFactory factory;

  /// Adapter capabilities.
  ///
  /// This is the declaration used *before* an adapter exists: the selector
  /// scores registrations by protocol, format and live support, and the
  /// kernel needs those answers without instantiating a backend.
  ///
  /// It is not the authority for a running adapter. Consumers that hold an
  /// instance read `adapter.capabilities`, because an adapter may be built
  /// with a narrower declaration than its default. Keep the two in step by
  /// handing the registration the adapter's own constant
  /// (`SomeAdapter.defaultCapabilities`) instead of repeating the literal.
  final PlayerAdapterCapabilities capabilities;

  /// Selection priority.
  ///
  /// Higher value means preferred.
  final int priority;

  /// Whether adapter is enabled.
  final bool enabled;

  /// Creates copy.
  PlayerAdapterRegistration copyWith({
    PlayerAdapterFactory? factory,
    PlayerAdapterCapabilities? capabilities,
    int? priority,
    bool? enabled,
  }) {
    return PlayerAdapterRegistration(
      id: id,
      factory: factory ?? this.factory,
      capabilities: capabilities ?? this.capabilities,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }
}
