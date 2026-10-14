import 'package:equatable/equatable.dart';
import 'package:media_core/platform/platform_provider.dart' show PlatformProvider;

/// Describes platform capabilities.
///
/// [PlatformCapabilities] represents what the
/// current runtime environment supports.
///
/// Responsibilities:
///
/// - codec capability
/// - rendering capability
/// - audio capability
/// - system feature support
///
/// It does not:
///
/// - detect platform
/// - query native APIs
/// - initialize resources
///
/// Those belong to:
///
/// - PlatformInfo
/// - PlatformProvider
final class PlatformCapabilities extends Equatable {
  /// Creates platform capabilities.
  const PlatformCapabilities({
    this.hardwareDecode = true,

    this.softwareDecode = true,

    this.videoRendering = true,

    this.audioPlayback = true,

    this.subtitleRendering = true,

    this.pictureInPicture = false,

    this.fullscreen = true,

    this.externalDisplay = false,

    this.backgroundPlayback = false,

    this.networkPlayback = true,

    this.localPlayback = true,

    this.reported = false,
  });

  /// Whether hardware decoding is supported.
  final bool hardwareDecode;

  /// Whether software decoding is supported.
  final bool softwareDecode;

  /// Whether video rendering is supported.
  final bool videoRendering;

  /// Whether audio playback is supported.
  final bool audioPlayback;

  /// Whether subtitle rendering is supported.
  final bool subtitleRendering;

  /// Whether PiP is supported.
  final bool pictureInPicture;

  /// Whether fullscreen is supported.
  final bool fullscreen;

  /// Whether external display is supported.
  final bool externalDisplay;

  /// Whether background playback is supported.
  final bool backgroundPlayback;

  /// Whether these answers came from a platform probe.
  ///
  /// `false` means every field above is a default rather than a fact — the
  /// state of every session that was created without a [PlatformProvider]
  /// attached. The defaults are deliberately optimistic; what this flag adds
  /// is the ability to tell "the platform said yes" from "nobody asked".
  final bool reported;

  /// Whether network playback is supported.
  final bool networkPlayback;

  /// Whether local playback is supported.
  final bool localPlayback;

  /// Whether any video decoder is available.
  bool get canDecodeVideo {
    return hardwareDecode || softwareDecode;
  }

  /// Whether video playback is possible.
  bool get canPlayVideo {
    return canDecodeVideo && videoRendering;
  }

  /// Whether audio playback is possible.
  bool get canPlayAudio {
    return audioPlayback;
  }

  /// Whether network source is supported.
  bool get canPlayNetwork {
    return networkPlayback;
  }

  /// Whether local source is supported.
  bool get canPlayLocal {
    return localPlayback;
  }

  /// Creates modified capabilities.
  PlatformCapabilities copyWith({
    bool? hardwareDecode,

    bool? softwareDecode,

    bool? videoRendering,

    bool? audioPlayback,

    bool? subtitleRendering,

    bool? pictureInPicture,

    bool? fullscreen,

    bool? externalDisplay,

    bool? backgroundPlayback,

    bool? networkPlayback,

    bool? localPlayback,
  }) {
    return PlatformCapabilities(
      hardwareDecode: hardwareDecode ?? this.hardwareDecode,

      softwareDecode: softwareDecode ?? this.softwareDecode,

      videoRendering: videoRendering ?? this.videoRendering,

      audioPlayback: audioPlayback ?? this.audioPlayback,

      subtitleRendering: subtitleRendering ?? this.subtitleRendering,

      pictureInPicture: pictureInPicture ?? this.pictureInPicture,

      fullscreen: fullscreen ?? this.fullscreen,

      externalDisplay: externalDisplay ?? this.externalDisplay,

      backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,

      networkPlayback: networkPlayback ?? this.networkPlayback,

      localPlayback: localPlayback ?? this.localPlayback,
    );
  }

  @override
  List<Object?> get props => [
    hardwareDecode,

    softwareDecode,

    videoRendering,

    audioPlayback,

    subtitleRendering,

    pictureInPicture,

    fullscreen,

    externalDisplay,

    backgroundPlayback,

    networkPlayback,

    localPlayback,

    reported,
  ];

  @override
  String toString() {
    return 'PlatformCapabilities('
        'decode=$canDecodeVideo, '
        'render=$videoRendering, '
        'pip=$pictureInPicture, '
        'background=$backgroundPlayback'
        ')';
  }
}
