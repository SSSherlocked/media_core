import 'package:media_core/media_core.dart';

import 'package:media_core_fvp/src/fvp_player_adapter.dart';
import 'package:media_core_fvp/src/fvp_video_config.dart';

export 'package:media_core_fvp/src/fvp_video_config.dart' show FvpVideoConfig;

/// Backend id the fvp (libmdk) adapter registers under.
const String kFvpPlayerBackendId = 'fvp';

/// [PlayerAdapterFactory] that creates [FvpPlayerAdapter] instances.
final class FvpAdapterFactory implements PlayerAdapterFactory {
  /// [capabilities] and the native mdk fields are shared by every
  /// adapter this factory creates. [configure] runs once per instance
  /// after construction for per-instance customisation.
  const FvpAdapterFactory({
    this.capabilities = FvpPlayerAdapter.defaultCapabilities,
    this.properties = const <String, String>{},
    this.videoDecoders,
    this.audioBackends,
    this.videoConfig = const FvpVideoConfig(),
    this.configure,
  });

  /// Capability set every adapter this factory creates reports.
  final PlayerAdapterCapabilities capabilities;

  /// Raw mdk properties applied to every adapter, before a source opens.
  final Map<String, String> properties;

  /// Video decoder list in preference order; null leaves mdk's default.
  final List<String>? videoDecoders;

  /// Audio backend list in preference order; null leaves mdk's default.
  final List<String>? audioBackends;

  /// How the texture each adapter owns is presented and sized.
  final FvpVideoConfig videoConfig;

  /// Runs once per adapter after construction, for per-instance customisation.
  final void Function(FvpPlayerAdapter adapter)? configure;

  @override
  PlayerAdapter create(String id) {
    final adapter = FvpPlayerAdapter(
      id: id,
      capabilities: capabilities,
      properties: properties,
      videoDecoders: videoDecoders,
      audioBackends: audioBackends,
      videoConfig: videoConfig,
    );

    configure?.call(adapter);

    return adapter;
  }

  @override
  bool supports(String id) => id == kFvpPlayerBackendId;

  /// Builds a registration entry for `PlayerKernel.registerBackend` or a
  /// [PlayerAdapterRegistry]. That path carries [capabilities] on the
  /// registration entry itself, so capability-based selection works before an
  /// adapter is ever instantiated.
  PlayerAdapterRegistration registration({int priority = 80}) {
    return PlayerAdapterRegistration(
      id: kFvpPlayerBackendId,
      factory: this,
      capabilities: capabilities,
      priority: priority,
    );
  }
}

/// Registers the fvp adapter in a [DefaultPlayerAdapterFactory].
void registerFvpFactory(
  DefaultPlayerAdapterFactory factory, {
  String id = kFvpPlayerBackendId,
  PlayerAdapterCapabilities capabilities = FvpPlayerAdapter.defaultCapabilities,
  Map<String, String> properties = const <String, String>{},
  List<String>? videoDecoders,
  List<String>? audioBackends,
  FvpVideoConfig videoConfig = const FvpVideoConfig(),
  void Function(FvpPlayerAdapter adapter)? configure,
}) {
  factory.register(id, () {
    final adapter = FvpPlayerAdapter(
      id: id,
      capabilities: capabilities,
      properties: properties,
      videoDecoders: videoDecoders,
      audioBackends: audioBackends,
      videoConfig: videoConfig,
    );

    configure?.call(adapter);

    return adapter;
  });
}

/// Registers the fvp adapter in a [PlayerAdapterRegistry].
void registerFvpRegistry(
  PlayerAdapterRegistry registry, {
  int priority = 80,
  PlayerAdapterCapabilities capabilities = FvpPlayerAdapter.defaultCapabilities,
  Map<String, String> properties = const <String, String>{},
  List<String>? videoDecoders,
  List<String>? audioBackends,
  FvpVideoConfig videoConfig = const FvpVideoConfig(),
  void Function(FvpPlayerAdapter adapter)? configure,
}) {
  registry.register(
    FvpAdapterFactory(
      capabilities: capabilities,
      properties: properties,
      videoDecoders: videoDecoders,
      audioBackends: audioBackends,
      videoConfig: videoConfig,
      configure: configure,
    ).registration(priority: priority),
  );
}
