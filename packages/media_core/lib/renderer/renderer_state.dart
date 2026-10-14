import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/renderer/renderer_capabilities.dart';
import 'package:media_core/renderer/renderer_config.dart';

/// Current renderer state.
///
/// Represents renderer lifecycle and presentation state.
///
/// The state is renderer-level state only.
///
/// It does not:
///
/// - create or destroy platform surfaces
/// - control the playback backend
/// - calculate video geometry
/// - perform platform-specific rendering
final class RendererState extends Equatable {
  /// Creates the renderer state from its fields.
  ///
  /// Nothing is derived here — [canRender] is where initialization, surface
  /// readiness, capability and configuration meet, and [initialize] is what
  /// normally produces a state worth storing.
  const RendererState({
    required this.config,
    required this.capabilities,
    required this.initialized,
    required this.rendering,
    required this.surfaceReady,
    required this.generation,
    required this.updatedAt,
  });

  /// Reads a state written by [toMap].
  ///
  /// An absent or malformed `config` becomes the default configuration, and an
  /// absent `capabilities` the empty set: a half-restored renderer starts out
  /// unable to render rather than claiming a surface it never had.
  factory RendererState.fromMap(Map<String, dynamic> map) {
    final Object? configValue = map['config'];
    final Object? capabilitiesValue = map['capabilities'];

    return RendererState(
      config: configValue is Map
          ? RendererConfig.fromMap(Map<String, dynamic>.from(configValue))
          : const RendererConfig.defaults(),
      capabilities: capabilitiesValue is Map
          ? RendererCapabilities.fromMap(Map<String, dynamic>.from(capabilitiesValue))
          : const RendererCapabilities.none(),
      initialized: map['initialized'] as bool? ?? false,
      rendering: map['rendering'] as bool? ?? false,
      surfaceReady: map['surfaceReady'] as bool? ?? false,
      generation: (map['generation'] as num?)?.toInt() ?? 0,
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  /// The state of a renderer that has never been initialized: no capabilities,
  /// nothing ready, nothing rendering, generation zero.
  const RendererState.initial()
    : config = const RendererConfig.defaults(),
      capabilities = const RendererCapabilities.none(),
      initialized = false,
      rendering = false,
      surfaceReady = false,
      generation = 0,
      updatedAt = null;

  /// Current renderer configuration.
  final RendererConfig config;

  /// Capabilities exposed by the current renderer.
  final RendererCapabilities capabilities;

  /// Whether the renderer has been initialized.
  final bool initialized;

  /// Whether rendering is currently active.
  final bool rendering;

  /// Whether the rendering surface is ready.
  final bool surfaceReady;

  /// Monotonically increasing renderer generation.
  ///
  /// A generation identifies one renderer lifecycle instance and allows
  /// asynchronous callbacks from an older renderer instance to be rejected.
  final int generation;

  /// Time when the state was last changed.
  final DateTime? updatedAt;

  /// Whether the renderer can currently render video.
  bool get canRender {
    return initialized && surfaceReady && capabilities.canRender && config.enabled;
  }

  /// Whether initialization and surface creation are both complete.
  bool get isReady {
    return initialized && surfaceReady;
  }

  /// Whether the renderer cannot render video.
  bool get isUnavailable {
    return !capabilities.canRender;
  }

  /// Creates a modified state.
  RendererState copyWith({
    RendererConfig? config,
    RendererCapabilities? capabilities,
    bool? initialized,
    bool? rendering,
    bool? surfaceReady,
    int? generation,
    DateTime? updatedAt,
  }) {
    return RendererState(
      config: config ?? this.config,
      capabilities: capabilities ?? this.capabilities,
      initialized: initialized ?? this.initialized,
      rendering: rendering ?? this.rendering,
      surfaceReady: surfaceReady ?? this.surfaceReady,
      generation: generation ?? this.generation,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Initializes the renderer.
  RendererState initialize({
    required RendererCapabilities capabilities,
    RendererConfig? config,
    int? generation,
    DateTime? updatedAt,
  }) {
    return RendererState(
      config: config ?? this.config,
      capabilities: capabilities,
      initialized: true,
      rendering: false,
      surfaceReady: false,
      generation: generation ?? this.generation,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Marks the rendering surface as ready or unavailable.
  RendererState markSurfaceReady({bool value = true, int? generation, DateTime? updatedAt}) {
    return RendererState(
      config: config,
      capabilities: capabilities,
      initialized: initialized,
      rendering: value && rendering,
      surfaceReady: value,
      generation: generation ?? this.generation,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Starts rendering.
  ///
  /// Rendering can only start after initialization and surface readiness.
  RendererState startRendering({DateTime? updatedAt}) {
    if (!initialized || !surfaceReady || !capabilities.canRender) {
      return this;
    }

    return RendererState(
      config: config,
      capabilities: capabilities,
      initialized: true,
      rendering: true,
      surfaceReady: true,
      generation: generation,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Stops rendering while keeping the renderer initialized.
  RendererState stopRendering({DateTime? updatedAt}) {
    return RendererState(
      config: config,
      capabilities: capabilities,
      initialized: initialized,
      rendering: false,
      surfaceReady: surfaceReady,
      generation: generation,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Advances the renderer generation.
  ///
  /// The generation is never allowed to decrease.
  RendererState nextGeneration({DateTime? updatedAt}) {
    return RendererState(
      config: config,
      capabilities: capabilities,
      initialized: false,
      rendering: false,
      surfaceReady: false,
      generation: generation + 1,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Resets the renderer while preserving its generation.
  RendererState reset({DateTime? updatedAt}) {
    return RendererState(
      config: config,
      capabilities: const RendererCapabilities.none(),
      initialized: false,
      rendering: false,
      surfaceReady: false,
      generation: generation,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// The `fromMap()` form.
  ///
  /// The generation is part of it on purpose: a restored state has to carry on
  /// the same renderer lifecycle, or reports from the surface it came back for
  /// would be rejected as stale.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'config': config.toMap(),
      'capabilities': capabilities.toMap(),
      'initialized': initialized,
      'rendering': rendering,
      'surfaceReady': surfaceReady,
      'generation': generation,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  @override
  List<Object?> get props => <Object?>[
    config,
    capabilities,
    initialized,
    rendering,
    surfaceReady,
    generation,
    updatedAt,
  ];

  @override
  String toString() {
    return 'RendererState('
        'config: $config, '
        'capabilities: $capabilities, '
        'initialized: $initialized, '
        'rendering: $rendering, '
        'surfaceReady: $surfaceReady, '
        'generation: $generation, '
        'updatedAt: $updatedAt'
        ')';
  }
}
