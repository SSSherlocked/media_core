import 'package:equatable/equatable.dart';

/// Renderer configuration.
///
/// Defines how a media renderer should present video.
///
/// This configuration is renderer-level data only.
///
/// It does not:
///
/// - create a rendering surface
/// - control a platform renderer
/// - manage video geometry
/// - control playback
final class RendererConfig extends Equatable {
  /// Declares how video should be presented: rendering on, aspect ratio
  /// preserved, mirrored off and hardware acceleration preferred.
  const RendererConfig({
    this.enabled = true,
    this.keepAspectRatio = true,
    this.fill = false,
    this.mirror = false,
    this.hardwareAcceleration = true,
    this.lowLatency = false,
  });

  /// Creates a configuration from a map.
  factory RendererConfig.fromMap(Map<String, dynamic> map) {
    return RendererConfig(
      enabled: map['enabled'] as bool? ?? true,
      keepAspectRatio: map['keepAspectRatio'] as bool? ?? true,
      fill: map['fill'] as bool? ?? false,
      mirror: map['mirror'] as bool? ?? false,
      hardwareAcceleration: map['hardwareAcceleration'] as bool? ?? true,
      lowLatency: map['lowLatency'] as bool? ?? false,
    );
  }

  /// Default renderer configuration.
  const RendererConfig.defaults()
    : enabled = true,
      keepAspectRatio = true,
      fill = false,
      mirror = false,
      hardwareAcceleration = true,
      lowLatency = false;

  /// Whether rendering is enabled.
  final bool enabled;

  /// Whether the source aspect ratio should be preserved.
  final bool keepAspectRatio;

  /// Whether the renderer should fill its available area.
  final bool fill;

  /// Whether the rendered image should be mirrored.
  final bool mirror;

  /// Whether hardware acceleration is preferred.
  final bool hardwareAcceleration;

  /// Whether low-latency rendering is preferred.
  final bool lowLatency;

  /// Creates a modified configuration.
  RendererConfig copyWith({
    bool? enabled,
    bool? keepAspectRatio,
    bool? fill,
    bool? mirror,
    bool? hardwareAcceleration,
    bool? lowLatency,
  }) {
    return RendererConfig(
      enabled: enabled ?? this.enabled,
      keepAspectRatio: keepAspectRatio ?? this.keepAspectRatio,
      fill: fill ?? this.fill,
      mirror: mirror ?? this.mirror,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      lowLatency: lowLatency ?? this.lowLatency,
    );
  }

  /// Converts the configuration to a map.
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'keepAspectRatio': keepAspectRatio,
      'fill': fill,
      'mirror': mirror,
      'hardwareAcceleration': hardwareAcceleration,
      'lowLatency': lowLatency,
    };
  }

  @override
  List<Object?> get props => [enabled, keepAspectRatio, fill, mirror, hardwareAcceleration, lowLatency];

  @override
  String toString() {
    return 'RendererConfig('
        'enabled=$enabled, '
        'keepAspectRatio=$keepAspectRatio, '
        'fill=$fill, '
        'mirror=$mirror, '
        'hardwareAcceleration='
        '$hardwareAcceleration, '
        'lowLatency=$lowLatency)';
  }
}
