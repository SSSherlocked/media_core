import 'package:media_core/media_core.dart' show CompositeMediaSource, UnsupportedPlan;

/// How a backend consumes a [CompositeMediaSource].
///
/// A composite source can be presented in more than one way, and the
/// difference matters for how the planner schedules the tracks:
///
/// - [none] — the backend takes exactly one URL. The planner answers
///   [UnsupportedPlan] for a composite here; nothing in the stack
///   merges two essences on the backend's behalf.
/// - [native] — the backend has a first-class API for merging essence
///   sources (e.g. Media3 / ExoPlayer's `MergingMediaSource`). The
///   planner hands the whole composite through unchanged.
/// - [externalAudio] — the backend plays one primary input and can
///   attach extra audio via its own side channel (e.g. MPV's
///   `audio-files` / `--secondary-sid`). The planner picks a primary
///   video track for the main pipeline and routes the rest through
///   the side channel.
///
/// Responsibilities:
///
/// - describe what a backend can do with composite sources
/// - drive planner branching
///
/// It does not:
///
/// - decide whether a specific source is currently playable
/// - express codec or protocol support
///
/// Those belong to:
///
/// - MediaSourcePlanner
/// - PlayerAdapterCapabilities
enum CompositeSupport {
  /// The backend cannot consume composite sources.
  none,

  /// The backend merges essence sources through its native API.
  native,

  /// The backend plays one primary input plus an externally attached
  /// audio stream.
  externalAudio,
}

/// Extensions for [CompositeSupport].
extension CompositeSupportX on CompositeSupport {
  /// Whether the backend can consume composite sources at all.
  bool get isSupported => this != CompositeSupport.none;

  /// Whether the backend merges composites natively.
  bool get isNative => this == CompositeSupport.native;

  /// Whether the backend needs an external audio side channel.
  bool get isExternalAudio => this == CompositeSupport.externalAudio;
}
