import 'package:equatable/equatable.dart';

/// Renderer capabilities.
///
/// Describes rendering features supported by the current renderer.
///
/// Capabilities are descriptive only.
///
/// They do not:
///
/// - enable or disable features
/// - create rendering surfaces
/// - call platform APIs
final class RendererCapabilities extends Equatable {
  /// Declares what a renderer can do, assuming a full-featured engine.
  ///
  /// [lowLatency] is the one flag that starts false: rendering with less
  /// buffering is a trade the engine has to opt into, never an assumption a
  /// consumer can make on its behalf.
  const RendererCapabilities({
    this.video = true,
    this.overlay = true,
    this.mirror = true,
    this.rotation = true,
    this.hardwareAcceleration = true,
    this.lowLatency = false,
  });

  /// Creates capabilities from a map.
  factory RendererCapabilities.fromMap(Map<String, dynamic> map) {
    return RendererCapabilities(
      video: map['video'] as bool? ?? true,
      overlay: map['overlay'] as bool? ?? true,
      mirror: map['mirror'] as bool? ?? true,
      rotation: map['rotation'] as bool? ?? true,
      hardwareAcceleration: map['hardwareAcceleration'] as bool? ?? true,
      lowLatency: map['lowLatency'] as bool? ?? false,
    );
  }

  /// Renderer with no supported capabilities.
  const RendererCapabilities.none()
    : video = false,
      overlay = false,
      mirror = false,
      rotation = false,
      hardwareAcceleration = false,
      lowLatency = false;

  /// Whether video rendering is supported.
  final bool video;

  /// Whether overlay rendering is supported.
  final bool overlay;

  /// Whether mirroring is supported.
  final bool mirror;

  /// Whether video rotation is supported.
  final bool rotation;

  /// Whether hardware acceleration is supported.
  final bool hardwareAcceleration;

  /// Whether low-latency rendering is supported.
  final bool lowLatency;

  /// Whether any rendering capability is available.
  bool get canRender => video;

  /// Whether all basic rendering capabilities are available.
  bool get isFullySupported {
    return video && overlay && mirror && rotation;
  }

  /// Whether the renderer can use the requested configuration.
  bool supports({
    bool overlay = false,
    bool mirror = false,
    bool rotation = false,
    bool hardwareAcceleration = false,
    bool lowLatency = false,
  }) {
    if (overlay && !this.overlay) {
      return false;
    }

    if (mirror && !this.mirror) {
      return false;
    }

    if (rotation && !this.rotation) {
      return false;
    }

    if (hardwareAcceleration && !this.hardwareAcceleration) {
      return false;
    }

    if (lowLatency && !this.lowLatency) {
      return false;
    }

    return true;
  }

  /// Creates a modified capability set.
  RendererCapabilities copyWith({
    bool? video,
    bool? overlay,
    bool? mirror,
    bool? rotation,
    bool? hardwareAcceleration,
    bool? lowLatency,
  }) {
    return RendererCapabilities(
      video: video ?? this.video,
      overlay: overlay ?? this.overlay,
      mirror: mirror ?? this.mirror,
      rotation: rotation ?? this.rotation,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      lowLatency: lowLatency ?? this.lowLatency,
    );
  }

  /// Converts capabilities to a map.
  Map<String, dynamic> toMap() {
    return {
      'video': video,
      'overlay': overlay,
      'mirror': mirror,
      'rotation': rotation,
      'hardwareAcceleration': hardwareAcceleration,
      'lowLatency': lowLatency,
    };
  }

  @override
  List<Object?> get props => [video, overlay, mirror, rotation, hardwareAcceleration, lowLatency];

  @override
  String toString() {
    return 'RendererCapabilities('
        'video=$video, '
        'overlay=$overlay, '
        'mirror=$mirror, '
        'rotation=$rotation, '
        'hardwareAcceleration='
        '$hardwareAcceleration, '
        'lowLatency=$lowLatency)';
  }
}
