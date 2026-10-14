import 'package:media_core/media_core.dart';
import 'package:media_core_ijk_player/src/flv_lzc_player_adapter.dart';

/// Backend id the ijkplayer adapter registers under.
const String kIjkPlayerBackendId = 'ijk';

/// [PlayerAdapterFactory] that creates [FlvLzcPlayerAdapter] instances.
final class FlvLzcPlayerAdapterFactory implements PlayerAdapterFactory {
  /// [capabilities] and [options] are shared by every adapter this
  /// factory creates. [configure] runs once per instance after
  /// construction for per-instance customisation.
  const FlvLzcPlayerAdapterFactory({
    this.capabilities = FlvLzcPlayerAdapter.defaultCapabilities,
    this.options = const <EngineOption>[],
    this.configure,
  });

  /// Capabilities reported for every adapter this factory creates.
  final PlayerAdapterCapabilities capabilities;

  /// Native ijkplayer options applied by every created adapter before
  /// each open.
  final List<EngineOption> options;

  /// Optional per-instance hook run after each adapter is constructed.
  final void Function(FlvLzcPlayerAdapter adapter)? configure;

  @override
  PlayerAdapter create(String id) {
    final adapter = FlvLzcPlayerAdapter(id: id, capabilities: capabilities, options: options);
    configure?.call(adapter);
    return adapter;
  }

  @override
  bool supports(String id) => id == kIjkPlayerBackendId;

  /// Builds a registration entry for `PlayerKernel.registerBackend`
  /// or a [PlayerAdapterRegistry]. That path carries [capabilities]
  /// on the registration entry itself, so capability-based selection
  /// works before an adapter is ever instantiated.
  PlayerAdapterRegistration registration({int priority = 90}) {
    return PlayerAdapterRegistration(
      id: kIjkPlayerBackendId,
      factory: this,
      capabilities: capabilities,
      priority: priority,
    );
  }
}

/// Registers the ijkplayer adapter in a [DefaultPlayerAdapterFactory].
void registerIjkFactory(
  DefaultPlayerAdapterFactory factory, {
  String id = kIjkPlayerBackendId,
  PlayerAdapterCapabilities capabilities = FlvLzcPlayerAdapter.defaultCapabilities,
  List<EngineOption> options = const <EngineOption>[],
  void Function(FlvLzcPlayerAdapter adapter)? configure,
}) {
  factory.register(id, () {
    final adapter = FlvLzcPlayerAdapter(id: id, capabilities: capabilities, options: options);
    configure?.call(adapter);
    return adapter;
  });
}

/// Registers the ijkplayer adapter in a [PlayerAdapterRegistry].
void registerIjkRegistry(
  PlayerAdapterRegistry registry, {
  int priority = 90,
  PlayerAdapterCapabilities capabilities = FlvLzcPlayerAdapter.defaultCapabilities,
  List<EngineOption> options = const <EngineOption>[],
  void Function(FlvLzcPlayerAdapter adapter)? configure,
}) {
  registry.register(
    FlvLzcPlayerAdapterFactory(
      capabilities: capabilities,
      options: options,
      configure: configure,
    ).registration(priority: priority),
  );
}
