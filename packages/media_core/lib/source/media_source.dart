import 'package:media_core/adapter/player_adapter_capabilities.dart' show PlayerAdapterCapabilities;
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:meta/meta.dart';

part 'progressive_media_source.dart';
part 'composite_media_source.dart';

/// Discriminator for the shape of a [MediaSource].
///
/// A [MediaSource] subclass reports its variant through [MediaSource.type]
/// so consumers can switch on the shape without a `is`-chain:
///
/// - [progressive]: one self-contained stream that already muxes
///   audio and video, e.g. MP4 / MKV files, HLS master playlists,
///   RTMP live lines.
/// - [composite]: several parallel essence streams that must be
///   presented together, e.g. DASH `video.m4s` + `audio.m4s`.
enum MediaSourceType {
  /// A single progressive stream.
  progressive,

  /// Multiple tracks combined into one logical source.
  composite,
}

/// A playable media input, expressed independently of any backend.
///
/// [MediaSource] is the value a provider hands to the playback stack.
/// It answers "what should play", never "how should it play" — MPV,
/// Media3, FijkPlayer and future backends each decide how to consume
/// the source based on their declared
/// [PlayerAdapterCapabilities.compositeSupport], so a Bilibili DASH
/// pair does not need to know which engine is listening.
///
/// The hierarchy is `sealed` so every consumer gets exhaustive
/// pattern-matching over [ProgressiveMediaSource] and
/// [CompositeMediaSource] at compile time.
///
/// Responsibilities:
///
/// - carry the shape of a playable input
/// - classify that shape via [type]
///
/// It does not:
///
/// - select a backend
/// - resolve or fetch any resource
/// - track playback state
///
/// Those belong to:
///
/// - MediaSourcePlanner
/// - PlayerKernel
/// - SourceService
/// - PlayerAdapter
sealed class MediaSource {
  /// Creates a media source.
  ///
  /// [live] declares whether the input is an on-demand asset or a
  /// never-ending stream. Providers set it from their own knowledge
  /// (a Bilibili live room, an HLS event with no duration); it is not
  /// something media_core infers, because a manifest without a
  /// `ProgramInformation` duration and a VOD file whose probe failed
  /// look identical from the URL alone.
  const MediaSource({this.live = false});

  /// The shape of this source.
  ///
  /// Adapters and planners match on this instead of `is`-testing every
  /// subclass, so adding a new [MediaSource] variant is a compile-time
  /// break for consumers rather than a silent fall-through.
  MediaSourceType get type;

  /// Whether this source is a never-ending live stream rather than an
  /// on-demand asset.
  final bool live;

  /// Whether this source is a live stream.
  bool get isLive => live;

  /// Whether this source is a single progressive stream.
  bool get isProgressive => type == MediaSourceType.progressive;

  /// Whether this source combines several essence tracks.
  bool get isComposite => type == MediaSourceType.composite;

  /// Every [MediaTrack] this source carries, in video → audio →
  /// subtitle order for composite sources and as a one-element list
  /// for progressive ones.
  ///
  /// A planner that only needs "any URL that must be reachable" can
  /// iterate this getter instead of branching on [type].
  List<MediaTrack> get tracks;
}
