import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The orientation a source is presented with.
///
/// Classified from geometry evidence, not from the device's screen: a phone
/// in portrait still presents a 16:9 stream as [landscape].
enum VideoOrientationKind {
  /// Nothing trustworthy has been observed yet, so callers use their fallback.
  unknown,

  /// Taller than wide: a vertical programme such as a short-video feed.
  portrait,

  /// Square enough that either orientation shows it without cutting picture.
  square,

  /// Wider than tall: the conventional 16:9 / 2.39:1 shape.
  landscape,
}

/// Host-side override for the presented orientation.
///
/// A room or channel often declares its programme shape before anything is
/// decoded, and that knowledge outranks a transient decoder anomaly.
enum SourceOrientationOverride {
  /// No override; the detected geometry decides.
  automatic,

  /// Present as portrait whatever the decoder reports.
  portrait,

  /// Present as landscape whatever the decoder reports.
  landscape,
}

/// How much vertical space a presentation reserves around the video.
enum PresentationDensityMode {
  /// A portrait video may grow to 60% of the available height, keeping the
  /// full control and danmaku band underneath it.
  balanced,

  /// A portrait video may grow to 78% of the height, with a slimmer reserved
  /// danmaku band: a denser room that trades programme space for less chrome.
  immersive,

  /// No growth at all: the video keeps its legacy 16:9 height whatever the
  /// source ratio, for hosts laid out around that assumption.
  compatibility,
}

/// Which evidence produced the geometry in a [VideoGeometrySnapshot].
///
/// The source is part of the snapshot because they are not equally powerful:
/// only [VideoGeometryEvidence.activeContent] (measured pixels) may carry crop
/// coordinates, and [VideoGeometryEvidence.cache] is provisional by
/// construction.
enum VideoGeometryEvidence {
  /// No observation yet.
  unknown,

  /// Carried over from this room's last stable snapshot by
  /// [PortraitStreamDetector.seed], so a reconnect does not flash 16:9 first.
  cache,

  /// Declared stream metadata (selected resolution, container track size):
  /// classifies the programme early, but proves nothing about the decoded
  /// canvas and never crops it.
  platformMetadata,

  /// Display width/height published by the renderer: the real native texture
  /// geometry, occasionally wrong while sample-aspect metadata settles.
  decoderMetadata,

  /// Off-path frame probe of the actual picture, fused with decoder
  /// dimensions; the only evidence trusted to crop.
  activeContent,
}

/// The black bars around the picture in one decoded frame, as fractions of the
/// frame's own edges (0.0–1.0 per side).
@immutable
class NormalizedVideoInsets {
  /// Creates insets from the four edge fractions; all zero means the whole
  /// frame is picture.
  const NormalizedVideoInsets({this.left = 0, this.top = 0, this.right = 0, this.bottom = 0});

  /// The no-crop value, used whenever nothing has been measured.
  static const none = NormalizedVideoInsets();

  /// Fraction of the frame width covered by the left bar.
  final double left;

  /// Fraction of the frame height covered by the top bar.
  final double top;

  /// Fraction of the frame width covered by the right bar.
  final double right;

  /// Fraction of the frame height covered by the bottom bar.
  final double bottom;

  /// Fraction of the frame width that is picture once the side bars are gone.
  double get widthFraction => (1 - left - right).clamp(0.0, 1.0);

  /// Fraction of the frame height that is picture once the top and bottom
  /// bars are gone.
  double get heightFraction => (1 - top - bottom).clamp(0.0, 1.0);

  /// Whether a bar is wide enough on any edge to be worth cropping.
  bool get hasCrop => left > 0.001 || top > 0.001 || right > 0.001 || bottom > 0.001;

  /// Whether these insets still leave a viewable picture.
  ///
  /// A probe that mistakes a dark scene for black bars reports insets that
  /// would crop most of the programme away; nothing that leaves less than a
  /// tenth of either axis is treated as evidence at all.
  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      right.isFinite &&
      bottom.isFinite &&
      left >= 0 &&
      top >= 0 &&
      right >= 0 &&
      bottom >= 0 &&
      widthFraction > 0.10 &&
      heightFraction > 0.10;

  /// Converts an encoded (whole-frame) aspect ratio into the picture's own
  /// aspect ratio.
  double applyToAspectRatio(double encodedAspectRatio) {
    if (!isValid || !encodedAspectRatio.isFinite || encodedAspectRatio <= 0) {
      return encodedAspectRatio;
    }
    return encodedAspectRatio * widthFraction / heightFraction;
  }

  /// Whether two observations describe the same bars.
  ///
  /// Repeated probes of one stream differ by a pixel or two at the edges, so
  /// agreement is judged with a tolerance instead of exact equality; without
  /// it, two consistent observations would never accumulate into evidence.
  bool isNear(NormalizedVideoInsets other, {double tolerance = 0.035}) {
    return (left - other.left).abs() <= tolerance &&
        (top - other.top).abs() <= tolerance &&
        (right - other.right).abs() <= tolerance &&
        (bottom - other.bottom).abs() <= tolerance;
  }
}

/// One off-path probe of the actual picture: where the bars are, and how much
/// to believe it.
@immutable
class ActiveVideoContentObservation {
  /// Creates an observation from measured [insets] and the probe's
  /// [confidence], optionally carrying the screenshot [canvasAspectRatio].
  const ActiveVideoContentObservation({required this.insets, required this.confidence, this.canvasAspectRatio = 0});

  /// Bars measured on the probed frame.
  final NormalizedVideoInsets insets;

  /// How sure the probe is, 0.0–1.0; only a high value is treated as evidence.
  final double confidence;

  /// Aspect ratio of the actual screenshot canvas used for this observation.
  ///
  /// Decoder metadata is occasionally stale or has an incorrect sample aspect
  /// ratio. Keeping the screenshot geometry with the detected insets prevents
  /// those two independent coordinate spaces from being mixed later.
  final double canvasAspectRatio;

  /// Zero means that the probe did not report its canvas and the current
  /// decoder canvas may be used. A non-zero value is independent geometry and
  /// must pass the same generous live-video bounds as platform metadata. This
  /// keeps corrupt screenshot dimensions from settling content evidence or
  /// erasing an otherwise trustworthy stream hint.
  bool get hasPlausibleCanvasAspectRatio =>
      canvasAspectRatio == 0 || (canvasAspectRatio.isFinite && canvasAspectRatio >= 0.30 && canvasAspectRatio <= 3.50);

  /// Whether this single observation is strong enough to count as evidence.
  ///
  /// Combines the geometry guard ([hasPlausibleCanvasAspectRatio]) with a high
  /// confidence bar, because one bad probe that resized the player is visible
  /// to the viewer immediately.
  bool get isReliable => insets.isValid && confidence.isFinite && confidence >= 0.86 && hasPlausibleCanvasAspectRatio;
}

/// The classified geometry of a source, frozen at one instant.
///
/// Everything a presentation mode needs to size itself: the encoded canvas,
/// the measured crop, the effective ratio, the committed orientation and which
/// evidence got there — resolved once so that no mode reinterprets the same
/// stream differently.
@immutable
class VideoGeometrySnapshot {
  /// Creates a snapshot from already-classified fields.
  const VideoGeometrySnapshot({
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.orientation,
    required this.candidateOrientation,
    required this.stableSampleCount,
    required this.confidence,
    required this.observedAt,
    this.activeContentInsets = NormalizedVideoInsets.none,
    this.activeContentConfidence = 0,
    this.activeContentCanvasAspectRatio = 0,
    this.sourceHintAspectRatio = 0,
    this.sourceHintConfidence = 0,
    this.sourceHintSource = '',
    this.evidence = VideoGeometryEvidence.decoderMetadata,
    this.isProvisional = false,
  });

  /// The starting state: no dimensions, no orientation, a safe 16:9 canvas.
  const VideoGeometrySnapshot.unknown()
    : width = 0,
      height = 0,
      aspectRatio = 16 / 9,
      orientation = VideoOrientationKind.unknown,
      candidateOrientation = VideoOrientationKind.unknown,
      stableSampleCount = 0,
      confidence = 0,
      observedAt = null,
      activeContentInsets = NormalizedVideoInsets.none,
      activeContentConfidence = 0,
      activeContentCanvasAspectRatio = 0,
      sourceHintAspectRatio = 0,
      sourceHintConfidence = 0,
      sourceHintSource = '',
      evidence = VideoGeometryEvidence.unknown,
      isProvisional = false;

  /// Frame width the snapshot was classified from, in pixels.
  ///
  /// Which frame that is depends on [evidence]: the decoded display size, the
  /// declared stream size, or — for a seeded snapshot — the room's ratio scaled
  /// onto a synthetic canvas.
  final int width;

  /// Frame height matching [width], in pixels.
  final int height;

  /// Ratio of the encoded canvas as observed (`width / height`).
  ///
  /// Kept separate from [effectiveAspectRatio]: this is what the evidence says
  /// about the whole frame, before a measured crop or a stream hint has
  /// corrected it.
  final double aspectRatio;

  /// Last orientation that passed the stability gate.
  final VideoOrientationKind orientation;

  /// Most recent raw candidate. It can differ briefly during a quality switch.
  final VideoOrientationKind candidateOrientation;

  /// How many consecutive samples agree with the current candidate.
  final int stableSampleCount;

  /// How decisively the observed ratio falls on its side of the square band,
  /// 0.0–1.0 (for a square classification, how close it is to exactly 1:1).
  final double confidence;

  /// When the sample that produced this snapshot arrived.
  final DateTime? observedAt;

  /// Bars measured by the frame probe, or [NormalizedVideoInsets.none].
  final NormalizedVideoInsets activeContentInsets;

  /// Confidence of the probe that produced [activeContentInsets].
  final double activeContentConfidence;

  /// Ratio of the canvas the probe looked at, so its bars can be applied to
  /// the right geometry instead of to the decoder's.
  final double activeContentCanvasAspectRatio;

  /// Ratio declared by stream metadata (selected resolution, container track).
  final double sourceHintAspectRatio;

  /// How much stream metadata the source reported for [sourceHintAspectRatio].
  final double sourceHintConfidence;

  /// Which component declared [sourceHintAspectRatio], for diagnosing a room
  /// whose metadata keeps losing to the decoder.
  final String sourceHintSource;

  /// Which evidence this snapshot's classification rests on.
  final VideoGeometryEvidence evidence;

  /// Whether the snapshot is a stand-in that later observations may replace.
  ///
  /// Provisional geometry is enough to keep the layout from jumping, but it
  /// never counts as [isStable], so no mode treats it as settled.
  final bool isProvisional;

  /// Whether the snapshot carries a usable size at all.
  ///
  /// Zero or non-finite geometry means "nothing observed yet", and the detector
  /// refuses to classify or resize on it. A seeded snapshot does pass this
  /// check — on ratio-derived dimensions, which is why [isProvisional] exists
  /// as a separate question.
  bool get hasValidDimensions => width > 0 && height > 0 && aspectRatio.isFinite;

  /// Whether the committed orientation and the latest candidate agree.
  ///
  /// [VideoPresentationPolicy.resolveCompactWindowAspectRatio] refuses to follow
  /// a portrait source's shape until this is true, so a single odd sample can
  /// never resize a small window.
  bool get isStable => orientation != VideoOrientationKind.unknown && orientation == candidateOrientation;

  /// Whether stream metadata is strong enough to be consulted at all.
  bool get hasTrustedSourceHint =>
      sourceHintAspectRatio.isFinite &&
      sourceHintAspectRatio > 0 &&
      sourceHintConfidence.isFinite &&
      sourceHintConfidence >= 0.90;

  /// Whether a frame probe has reported usable geometry.
  bool get hasActiveContentObservation =>
      activeContentConfidence.isFinite &&
      activeContentConfidence >= 0.86 &&
      activeContentCanvasAspectRatio.isFinite &&
      activeContentCanvasAspectRatio > 0;

  /// Whether the probe measured bars worth cropping.
  bool get hasActiveContentCrop => hasActiveContentObservation && activeContentInsets.hasCrop;

  /// A strong portrait stream hint paired with a plausible landscape decoder
  /// canvas is the one case that needs pixel inspection. It may be a vertical
  /// programme embedded inside pillar bars, or simply stale platform metadata.
  /// Inspecting every ordinary landscape room is both expensive and unsafe: a
  /// dark scene can otherwise be mistaken for black bars and resize all modes.
  bool get hasTrustedPortraitHintOnLandscapeCanvas =>
      hasTrustedSourceHint && sourceHintAspectRatio < 0.90 && aspectRatio >= 1.10;

  /// Whether the declared stream ratio replaces the decoded canvas ratio.
  ///
  /// Only for obviously malformed decoder metadata; see the note on
  /// [renderCanvasAspectRatio] for the same rule applied to the canvas.
  bool get sourceHintOverridesDecoder =>
      hasTrustedSourceHint && _sourceHintShouldOverrideDecoder(aspectRatio, sourceHintAspectRatio);

  /// The ratio of the picture itself, after bars and after metadata repairs.
  ///
  /// A measured frame always wins (it is the only direct evidence), then a
  /// trusted stream hint that outranks bad decoder geometry, then the decoded
  /// canvas.
  double get effectiveAspectRatio {
    if (hasActiveContentObservation) {
      return activeContentInsets.applyToAspectRatio(activeContentCanvasAspectRatio);
    }
    if (sourceHintOverridesDecoder) return sourceHintAspectRatio;
    return aspectRatio;
  }

  /// Geometry used to size the native texture before applying a measured crop.
  ///
  /// Presentation geometry and decoder canvas geometry are deliberately kept
  /// separate. A platform hint may classify a room as portrait, but it does not
  /// prove that a landscape decoder canvas contains symmetric pillar bars. Only
  /// a frame observation may crop such a canvas. Extremely malformed decoder
  /// ratios still fall back to strong source metadata.
  double get renderCanvasAspectRatio {
    if (hasActiveContentObservation) return activeContentCanvasAspectRatio;
    if (sourceHintOverridesDecoder &&
        (aspectRatio < VideoPresentationPolicy.androidPipMinimumAspectRatio ||
            aspectRatio > VideoPresentationPolicy.androidPipMaximumAspectRatio)) {
      return sourceHintAspectRatio;
    }
    return aspectRatio;
  }

  /// The same snapshot with the listed fields replaced.
  ///
  /// A null argument keeps the current value, which is what lets the detector
  /// fold in one new piece of evidence without relaying out the rest.
  VideoGeometrySnapshot copyWith({
    int? width,
    int? height,
    double? aspectRatio,
    VideoOrientationKind? orientation,
    VideoOrientationKind? candidateOrientation,
    int? stableSampleCount,
    double? confidence,
    DateTime? observedAt,
    NormalizedVideoInsets? activeContentInsets,
    double? activeContentConfidence,
    double? activeContentCanvasAspectRatio,
    double? sourceHintAspectRatio,
    double? sourceHintConfidence,
    String? sourceHintSource,
    VideoGeometryEvidence? evidence,
    bool? isProvisional,
  }) {
    return VideoGeometrySnapshot(
      width: width ?? this.width,
      height: height ?? this.height,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      orientation: orientation ?? this.orientation,
      candidateOrientation: candidateOrientation ?? this.candidateOrientation,
      stableSampleCount: stableSampleCount ?? this.stableSampleCount,
      confidence: confidence ?? this.confidence,
      observedAt: observedAt ?? this.observedAt,
      activeContentInsets: activeContentInsets ?? this.activeContentInsets,
      activeContentConfidence: activeContentConfidence ?? this.activeContentConfidence,
      activeContentCanvasAspectRatio: activeContentCanvasAspectRatio ?? this.activeContentCanvasAspectRatio,
      sourceHintAspectRatio: sourceHintAspectRatio ?? this.sourceHintAspectRatio,
      sourceHintConfidence: sourceHintConfidence ?? this.sourceHintConfidence,
      sourceHintSource: sourceHintSource ?? this.sourceHintSource,
      evidence: evidence ?? this.evidence,
      isProvisional: isProvisional ?? this.isProvisional,
    );
  }
}

/// Event-driven video geometry classifier.
///
/// Decoder width and height often arrive as two independent events. A quality
/// or CDN switch can therefore expose one mixed pair for a few milliseconds.
/// This detector commits an orientation after three equal observations or a
/// 500 ms stable interval and uses a neutral band around 1:1 to avoid rotation
/// chatter for square and near-square sources.
class PortraitStreamDetector {
  /// Creates a detector with the sample count and timing it gates on.
  PortraitStreamDetector({
    this.requiredSamples = 3,
    this.stabilityDelay = const Duration(milliseconds: 500),
    this.portraitThreshold = 0.90,
    this.landscapeThreshold = 1.10,
  });

  /// How many consecutive samples must agree before an orientation commits.
  final int requiredSamples;

  /// How long a candidate must survive before it commits without reaching
  /// [requiredSamples] agreements — the path that still classifies a decoder
  /// which publishes its dimensions only once (see [commitPending]).
  final Duration stabilityDelay;

  /// Ratios at or below this are portrait.
  final double portraitThreshold;

  /// Ratios at or above this are landscape; between the two lies the neutral
  /// square band that stops near-square sources oscillating.
  final double landscapeThreshold;

  VideoGeometrySnapshot _snapshot = const VideoGeometrySnapshot.unknown();
  VideoOrientationKind _pending = VideoOrientationKind.unknown;
  DateTime? _pendingSince;
  int _pendingSamples = 0;
  ActiveVideoContentObservation? _pendingContent;
  int _pendingContentSamples = 0;
  bool _contentEvidenceSettled = false;

  /// The classification as it stands, updated by every observe call.
  VideoGeometrySnapshot get snapshot => _snapshot;

  /// When the currently pending candidate was first seen, or null if none is.
  DateTime? get pendingSince => _pendingSince;

  /// Whether an orientation is waiting out the stability gate.
  bool get hasPendingCandidate => _pending != VideoOrientationKind.unknown;

  /// Whether frame-probe evidence has been committed by this detector.
  ///
  /// False means a probe is still only accumulating: [observeActiveContent]
  /// needs two mutually consistent observations before it believes one, and a
  /// new source hint or a pending-evidence reset puts it back to false.
  bool get contentEvidenceSettled => _contentEvidenceSettled;

  /// Forgets everything, back to the unknown 16:9 snapshot.
  VideoGeometrySnapshot reset() {
    _pending = VideoOrientationKind.unknown;
    _pendingSince = null;
    _pendingSamples = 0;
    _pendingContent = null;
    _pendingContentSamples = 0;
    _contentEvidenceSettled = false;

    return _snapshot = const VideoGeometrySnapshot.unknown();
  }

  /// Drops the uncommitted samples and the pending probe, keeping the last
  /// committed classification.
  ///
  /// Used when the source changed in a way that invalidates the accumulating
  /// evidence but not the room's known shape.
  void resetPendingEvidence() {
    _clearPending();
    _pendingContent = null;
    _pendingContentSamples = 0;
    _contentEvidenceSettled = false;
  }

  /// Seeds the next decoder session from a recent stable room snapshot. It is
  /// explicitly provisional: fresh decoder/content observations replace it,
  /// while the UI avoids a visible 16:9 -> portrait jump during reconnects.
  VideoGeometrySnapshot seed(VideoGeometrySnapshot cached) {
    if (!cached.isStable || !cached.hasValidDimensions) return reset();
    resetPendingEvidence();
    final ratio = cached.effectiveAspectRatio;
    // A seeded snapshot carries no real pixels, so the room's ratio is scaled
    // onto a synthetic canvas: downstream code asks for dimensions, and 16:9
    // versus 9:16 has to read as "known" rather than as "not observed yet".
    const basis = 10000;

    return _snapshot = VideoGeometrySnapshot(
      width: (ratio * basis).round(),
      height: basis,
      aspectRatio: ratio,
      orientation: cached.orientation,
      candidateOrientation: cached.orientation,
      stableSampleCount: requiredSamples,
      confidence: cached.confidence,
      observedAt: cached.observedAt,
      evidence: VideoGeometryEvidence.cache,
      isProvisional: true,
    );
  }

  /// Starts a new URL/quality/CDN generation without carrying a crop measured
  /// on the previous decoded canvas. The last effective ratio remains as a
  /// provisional frame until platform or decoder metadata for the new source
  /// arrives, preventing both a visible jump and stale double-cropping.
  VideoGeometrySnapshot beginSourceTransition() {
    if (!_snapshot.isStable || !_snapshot.hasValidDimensions) return reset();
    return seed(_snapshot);
  }

  /// Commits strong platform stream metadata immediately. Decoder dimensions
  /// still replace the encoded-canvas fields later, while this declared content
  /// ratio remains available to repair malformed sample-aspect metadata and to
  /// classify the initial programme until the decoder publishes a plausible
  /// post-rotation display size.
  VideoGeometrySnapshot observeSourceMetadata(
    int width,
    int height, {
    required double confidence,
    required String source,
    DateTime? now,
  }) {
    if (width <= 0 || height <= 0 || !confidence.isFinite || confidence <= 0) {
      return _snapshot;
    }
    final ratio = width / height;
    if (!ratio.isFinite || ratio <= 0) return _snapshot;
    final orientation = _classifyWithoutHysteresis(ratio);
    _clearPending();
    _pendingContent = null;
    _pendingContentSamples = 0;
    _contentEvidenceSettled = false;

    return _snapshot = VideoGeometrySnapshot(
      width: width,
      height: height,
      aspectRatio: ratio,
      orientation: orientation,
      candidateOrientation: orientation,
      stableSampleCount: requiredSamples,
      confidence: confidence.clamp(0.0, 1.0),
      observedAt: now ?? DateTime.now(),
      sourceHintAspectRatio: ratio,
      sourceHintConfidence: confidence.clamp(0.0, 1.0),
      sourceHintSource: source,
      evidence: VideoGeometryEvidence.platformMetadata,
      isProvisional: true,
    );
  }

  /// Records one decoded size ([width] x [height]) and returns the resulting
  /// classification.
  ///
  /// Nothing commits on the first unusual sample: a candidate orientation has
  /// to reach [requiredSamples] agreements or survive [stabilityDelay] before
  /// [VideoGeometrySnapshot.orientation] moves, which is what keeps a
  /// half-updated width/height pair from flipping the layout mid-transition.
  VideoGeometrySnapshot observe(int width, int height, {DateTime? now}) {
    if (width <= 0 || height <= 0) return _snapshot;
    final timestamp = now ?? DateTime.now();
    final encodedRatio = width / height;
    if (!encodedRatio.isFinite || encodedRatio <= 0) return _snapshot;
    // A screenshot and decoder metadata are separate evidence sources. Do not
    // discard a settled visual observation merely because malformed decoder
    // dimensions disagree with its canvas. New URLs/qualities already enter a
    // fresh geometry generation through [beginSourceTransition].
    final ratio = _snapshot.hasActiveContentObservation
        ? _snapshot.activeContentInsets.applyToAspectRatio(_snapshot.activeContentCanvasAspectRatio)
        : _snapshot.hasTrustedSourceHint &&
              _sourceHintShouldOverrideDecoder(encodedRatio, _snapshot.sourceHintAspectRatio)
        ? _snapshot.sourceHintAspectRatio
        : encodedRatio;

    final candidate = _classify(ratio);
    if (candidate == _snapshot.orientation && candidate != VideoOrientationKind.unknown) {
      _clearPending();

      return _snapshot = _buildSnapshot(
        width: width,
        height: height,
        ratio: ratio,
        encodedRatio: encodedRatio,
        orientation: candidate,
        candidate: candidate,
        samples: requiredSamples,
        observedAt: timestamp,
      );
    }

    if (_pending == candidate) {
      _pendingSamples++;
    } else {
      _pending = candidate;
      _pendingSince = timestamp;
      _pendingSamples = 1;
    }

    final stableFor = timestamp.difference(_pendingSince!);
    final shouldCommit = _pendingSamples >= requiredSamples || stableFor >= stabilityDelay;
    _snapshot = _buildSnapshot(
      width: width,
      height: height,
      ratio: ratio,
      encodedRatio: encodedRatio,
      orientation: shouldCommit ? candidate : _snapshot.orientation,
      candidate: candidate,
      samples: _pendingSamples,
      observedAt: timestamp,
    );
    if (shouldCommit) _clearPending();
    return _snapshot;
  }

  /// Fuses an off-path, low-resolution frame probe with decoder metadata.
  /// Two mutually consistent observations are required. This prevents a dark
  /// scene, transition frame or danmaku overlay from resizing all player modes.
  VideoGeometrySnapshot observeActiveContent(ActiveVideoContentObservation observation, {DateTime? now}) {
    if (!_snapshot.hasValidDimensions || !observation.isReliable) {
      return _snapshot;
    }
    final canvasRatio = observation.canvasAspectRatio.isFinite && observation.canvasAspectRatio > 0
        ? observation.canvasAspectRatio
        : _snapshot.aspectRatio;
    if (observation.insets.hasCrop && !_isPlausibleActiveContentCrop(canvasRatio, observation.insets)) {
      _pendingContent = null;
      _pendingContentSamples = 0;
      return _snapshot;
    }
    final pending = _pendingContent;
    final sameCanvas =
        pending == null ||
        pending.canvasAspectRatio <= 0 ||
        observation.canvasAspectRatio <= 0 ||
        _relativeRatioDifference(pending.canvasAspectRatio, observation.canvasAspectRatio) <= 0.04;
    if ((pending?.insets.isNear(observation.insets) ?? false) && sameCanvas) {
      _pendingContentSamples++;
      if (observation.confidence > pending!.confidence) {
        _pendingContent = observation;
      }
    } else {
      _pendingContent = observation;
      _pendingContentSamples = 1;
    }
    if (_pendingContentSamples < 2) return _snapshot;

    final accepted = _pendingContent!;
    _pendingContent = null;
    _pendingContentSamples = 0;
    _contentEvidenceSettled = true;
    final acceptedCanvasRatio = accepted.canvasAspectRatio.isFinite && accepted.canvasAspectRatio > 0
        ? accepted.canvasAspectRatio
        : _snapshot.aspectRatio;
    final effectiveRatio = accepted.insets.applyToAspectRatio(acceptedCanvasRatio);
    final orientation = _classifyWithoutHysteresis(effectiveRatio);
    final clearContradictedHint =
        _snapshot.hasTrustedSourceHint &&
        _relativeRatioDifference(effectiveRatio, _snapshot.sourceHintAspectRatio) > 0.16;
    _clearPending();

    return _snapshot = _snapshot.copyWith(
      orientation: orientation,
      candidateOrientation: orientation,
      stableSampleCount: requiredSamples,
      confidence: math.max(_snapshot.confidence, accepted.confidence),
      observedAt: now ?? DateTime.now(),
      activeContentInsets: accepted.insets,
      activeContentConfidence: accepted.confidence,
      activeContentCanvasAspectRatio: acceptedCanvasRatio,
      sourceHintAspectRatio: clearContradictedHint ? 0 : _snapshot.sourceHintAspectRatio,
      sourceHintConfidence: clearContradictedHint ? 0 : _snapshot.sourceHintConfidence,
      sourceHintSource: clearContradictedHint ? '' : _snapshot.sourceHintSource,
      evidence: VideoGeometryEvidence.activeContent,
      isProvisional: false,
    );
  }

  /// Commits the last unchanged candidate after [stabilityDelay] even if the
  /// decoder emits dimensions only once.
  VideoGeometrySnapshot commitPending({DateTime? now}) {
    final since = _pendingSince;
    if (since == null || _pending == VideoOrientationKind.unknown) {
      return _snapshot;
    }
    final timestamp = now ?? DateTime.now();
    if (timestamp.difference(since) < stabilityDelay || !_snapshot.hasValidDimensions) {
      return _snapshot;
    }
    _snapshot = _snapshot.copyWith(
      orientation: _pending,
      candidateOrientation: _pending,
      stableSampleCount: math.max(_pendingSamples, 1),
      observedAt: timestamp,
    );
    _clearPending();
    return _snapshot;
  }

  VideoOrientationKind _classify(double ratio) {
    // Hysteresis keeps an established orientation until it has crossed well
    // into the square band. This is especially useful for rotated metadata
    // during adaptive-quality transitions.
    if (_snapshot.orientation == VideoOrientationKind.portrait && ratio < 0.96) {
      return VideoOrientationKind.portrait;
    }
    if (_snapshot.orientation == VideoOrientationKind.landscape && ratio > 1.04) {
      return VideoOrientationKind.landscape;
    }
    if (ratio <= portraitThreshold) return VideoOrientationKind.portrait;
    if (ratio >= landscapeThreshold) return VideoOrientationKind.landscape;
    return VideoOrientationKind.square;
  }

  VideoOrientationKind _classifyWithoutHysteresis(double ratio) {
    if (ratio <= portraitThreshold) return VideoOrientationKind.portrait;
    if (ratio >= landscapeThreshold) return VideoOrientationKind.landscape;
    return VideoOrientationKind.square;
  }

  VideoGeometrySnapshot _buildSnapshot({
    required int width,
    required int height,
    required double ratio,
    required double encodedRatio,
    required VideoOrientationKind orientation,
    required VideoOrientationKind candidate,
    required int samples,
    required DateTime observedAt,
  }) {
    final distance = (ratio - 1).abs();
    final confidence = candidate == VideoOrientationKind.square
        ? (1 - distance / 0.10).clamp(0.0, 1.0)
        : (distance / 0.33).clamp(0.0, 1.0);
    return VideoGeometrySnapshot(
      width: width,
      height: height,
      aspectRatio: encodedRatio,
      orientation: orientation,
      candidateOrientation: candidate,
      stableSampleCount: samples,
      confidence: confidence,
      observedAt: observedAt,
      activeContentInsets: _snapshot.activeContentInsets,
      activeContentConfidence: _snapshot.activeContentConfidence,
      activeContentCanvasAspectRatio: _snapshot.activeContentCanvasAspectRatio,
      sourceHintAspectRatio: _snapshot.sourceHintAspectRatio,
      sourceHintConfidence: _snapshot.sourceHintConfidence,
      sourceHintSource: _snapshot.sourceHintSource,
      evidence: _snapshot.hasActiveContentObservation
          ? VideoGeometryEvidence.activeContent
          : _snapshot.hasTrustedSourceHint &&
                _sourceHintShouldOverrideDecoder(encodedRatio, _snapshot.sourceHintAspectRatio)
          ? VideoGeometryEvidence.platformMetadata
          : VideoGeometryEvidence.decoderMetadata,
    );
  }

  void _clearPending() {
    _pending = VideoOrientationKind.unknown;
    _pendingSince = null;
    _pendingSamples = 0;
  }
}

double _relativeRatioDifference(double left, double right) {
  if (!left.isFinite || !right.isFinite || left <= 0 || right <= 0) {
    return double.infinity;
  }
  return (left - right).abs() / math.max(left, right);
}

bool _sourceHintShouldOverrideDecoder(double encodedRatio, double sourceHintRatio) {
  if (!encodedRatio.isFinite || encodedRatio <= 0 || !sourceHintRatio.isFinite || sourceHintRatio <= 0) {
    return false;
  }
  // A selected-stream resolution is useful before decoding starts, but the
  // first plausible post-rotation dw/dh pair is the actual native texture
  // geometry. Orientation disagreement alone is not evidence that the texture
  // contains black bars. Keep the hint only for obviously malformed sample
  // aspect metadata; active-frame evidence handles real embedded content.
  return encodedRatio < VideoPresentationPolicy.androidPipMinimumAspectRatio ||
      encodedRatio > VideoPresentationPolicy.androidPipMaximumAspectRatio;
}

/// Whether an off-path frame probe can add evidence that decoder metadata does
/// not already provide. Kept pure so the performance gate is regression-tested
/// independently from player timers and native screenshot APIs.
bool shouldInspectActiveVideoContent(VideoGeometrySnapshot snapshot) {
  return snapshot.hasActiveContentCrop || snapshot.hasTrustedPortraitHintOnLandscapeCanvas;
}

bool _isPlausibleActiveContentCrop(double encodedRatio, NormalizedVideoInsets insets) {
  if (!insets.hasCrop || !insets.isValid || !encodedRatio.isFinite || encodedRatio <= 0) {
    return !insets.hasCrop;
  }
  final horizontalShare = insets.left + insets.right;
  final verticalShare = insets.top + insets.bottom;
  final effectiveRatio = insets.applyToAspectRatio(encodedRatio);
  if (!effectiveRatio.isFinite ||
      effectiveRatio < VideoPresentationPolicy.androidPipMinimumAspectRatio ||
      effectiveRatio > VideoPresentationPolicy.androidPipMaximumAspectRatio) {
    return false;
  }
  if (horizontalShare >= verticalShare) {
    // Side bars only establish a portrait programme when the decoded canvas is
    // landscape. Applying them to an already portrait frame creates the narrow
    // strip regression this gate is designed to prevent.
    return encodedRatio >= 1.10;
  }
  return encodedRatio <= 0.90;
}

/// A picture-in-picture ratio as an integer pair.
///
/// Platform PiP APIs take a rational aspect ratio, not a double, so the
/// clamped ratio is handed over as the two numbers they expect.
@immutable
class PipAspectRatio {
  /// Creates the ratio from its numerator and denominator.
  const PipAspectRatio(this.width, this.height);

  /// Numerator of the ratio.
  final int width;

  /// Denominator of the ratio.
  final int height;

  /// The ratio as a double, for layout maths.
  double get value => width / height;
}

/// Immutable geometry consumed by every presentation mode.
///
/// The normal portrait room, landscape fullscreen, the desktop small window
/// and system picture-in-picture must never independently reinterpret decoder
/// or platform metadata. They receive the same canvas, content and crop
/// decision; only their surrounding controls and window constraints differ.
@immutable
class VideoPresentationGeometry {
  /// Creates the resolved geometry bundle.
  const VideoPresentationGeometry({
    required this.canvasAspectRatio,
    required this.contentAspectRatio,
    required this.contentInsets,
    required this.orientation,
    required this.evidence,
    required this.isStable,
  });

  /// Ratio of the native texture the renderer fills.
  final double canvasAspectRatio;

  /// Ratio of the picture inside that texture, after any crop.
  final double contentAspectRatio;

  /// Crop to apply to the canvas, or [NormalizedVideoInsets.none].
  final NormalizedVideoInsets contentInsets;

  /// The orientation this geometry is presented as.
  final VideoOrientationKind orientation;

  /// Which evidence the decision rests on, so a mode can tell measured pixels
  /// from declared metadata.
  final VideoGeometryEvidence evidence;

  /// Whether the snapshot behind this geometry has settled: stable orientation
  /// and nothing provisional left in it.
  final bool isStable;

  /// Whether the crop here was measured from pixels rather than inferred.
  bool get hasMeasuredCrop => contentInsets.hasCrop && evidence == VideoGeometryEvidence.activeContent;
}

/// The shared ratio and layout rules every presentation mode resolves through.
///
/// Pure functions that turn geometry evidence into the numbers a mode lays out
/// with: keeping them out of the widgets and the drivers is what makes the
/// fallbacks below testable without a player, a screenshot API or a window
/// manager.
class VideoPresentationPolicy {
  const VideoPresentationPolicy._();

  /// Narrowest aspect ratio Android accepts for picture-in-picture (1/2.39).
  ///
  /// A decoder-reported ratio outside this band is therefore clamped by
  /// [resolveAndroidPipAspectRatio] rather than handed to the platform as it
  /// came; the same band is the sanity check on every other live ratio here.
  static const double androidPipMinimumAspectRatio = 1 / 2.39;

  /// Widest aspect ratio Android accepts for picture-in-picture (2.39).
  static const double androidPipMaximumAspectRatio = 2.39;

  /// Bundles a snapshot into the one geometry description every mode consumes.
  ///
  /// [effectiveOrientation] is the caller's decision (it may be a host
  /// override), and the ratio and crop are then resolved to agree with it
  /// rather than with whatever the decoder last reported.
  static VideoPresentationGeometry resolvePresentationGeometry({
    required VideoGeometrySnapshot snapshot,
    required VideoOrientationKind effectiveOrientation,
  }) {
    final contentAspectRatio = resolveVideoDisplayAspectRatio(
      snapshot: snapshot,
      effectiveOrientation: effectiveOrientation,
    );
    return VideoPresentationGeometry(
      canvasAspectRatio: snapshot.renderCanvasAspectRatio,
      contentAspectRatio: contentAspectRatio,
      contentInsets: resolveVideoContentInsets(snapshot: snapshot, presentationAspectRatio: contentAspectRatio),
      orientation: effectiveOrientation,
      evidence: snapshot.evidence,
      isStable: snapshot.isStable && !snapshot.isProvisional,
    );
  }

  /// Resolves the one aspect ratio used to present a native video texture.
  ///
  /// Some live CDNs expose a decoded buffer size whose sample-aspect metadata
  /// is temporarily malformed. Letting that raw ratio drive a texture directly
  /// can turn a regular 9:16 stream into a very narrow strip. The established
  /// orientation (including a room override) is therefore the authority:
  /// plausible ratios in the same orientation are preserved, while conflicting
  /// or out-of-range metadata falls back to the conventional live ratio.
  static double resolveVideoDisplayAspectRatio({
    required VideoGeometrySnapshot snapshot,
    required VideoOrientationKind effectiveOrientation,
  }) {
    final ratio = snapshot.effectiveAspectRatio;
    final valid = snapshot.hasValidDimensions && ratio > 0;
    return switch (effectiveOrientation) {
      VideoOrientationKind.portrait => valid && ratio >= androidPipMinimumAspectRatio && ratio < 0.90 ? ratio : 9 / 16,
      VideoOrientationKind.landscape => valid && ratio > 1.10 && ratio <= androidPipMaximumAspectRatio ? ratio : 16 / 9,
      VideoOrientationKind.square => valid && ratio >= 0.90 && ratio <= 1.10 ? ratio : 1.0,
      VideoOrientationKind.unknown => 16 / 9,
    };
  }

  /// Resolves the crop that is valid for the final presentation ratio.
  ///
  /// A measured crop is accepted only when applying it to the observed frame
  /// canvas produces that same ratio. Generic room metadata never invents crop
  /// coordinates. Selected-stream dimensions classify the programme early but
  /// never manufacture pixel crop coordinates.
  static NormalizedVideoInsets resolveVideoContentInsets({
    required VideoGeometrySnapshot snapshot,
    required double presentationAspectRatio,
  }) {
    final measured = resolveConsistentVideoContentInsets(
      encodedAspectRatio: snapshot.renderCanvasAspectRatio,
      presentationAspectRatio: presentationAspectRatio,
      contentInsets: snapshot.hasActiveContentCrop ? snapshot.activeContentInsets : NormalizedVideoInsets.none,
    );
    if (snapshot.hasActiveContentObservation || measured.hasCrop) {
      return measured;
    }

    // Platform metadata may arrive before the first decoder event, but it
    // carries no pixel coordinates. Treating a ratio mismatch as proof of
    // symmetric bars applies a second crop to a direct portrait texture when a
    // stale landscape event is observed. Only decoded-frame pixels may crop.
    return NormalizedVideoInsets.none;
  }

  /// Decides the orientation a mode should present as.
  ///
  /// A host override always wins. Otherwise detection is trusted only once the
  /// snapshot has settled — while it is still provisional the layout stays on
  /// the established landscape, because acting on a guess is what produced the
  /// narrow-strip regressions this policy exists to prevent.
  static VideoOrientationKind resolveOrientation({
    required VideoGeometrySnapshot snapshot,
    required SourceOrientationOverride override,
    required bool smartDetectionEnabled,
  }) {
    return switch (override) {
      SourceOrientationOverride.portrait => VideoOrientationKind.portrait,
      SourceOrientationOverride.landscape => VideoOrientationKind.landscape,
      SourceOrientationOverride.automatic =>
        smartDetectionEnabled && !snapshot.isProvisional ? snapshot.orientation : VideoOrientationKind.landscape,
    };
  }

  /// Height of the video slot in the ordinary in-page layout.
  ///
  /// A portrait programme can fill much more of a phone screen than the legacy
  /// 16:9 band, but growing it steals height from the danmaku and control area,
  /// so the result is clamped between the legacy height and whatever
  /// [mode] allows to be taken from those panels.
  static double resolveNormalVideoHeight({
    required double availableWidth,
    required double availableHeight,
    required bool isPortraitSource,
    required double sourceAspectRatio,
    required bool adaptiveHeightEnabled,
    required PresentationDensityMode mode,
    double resolutionHeight = 45,
    double minimumDanmakuHeight = 200,
  }) {
    if (!availableWidth.isFinite || availableWidth <= 0 || !availableHeight.isFinite || availableHeight <= 0) {
      return 0;
    }
    final legacyHeight = math.min(availableHeight, availableWidth / (16 / 9));
    if (!isPortraitSource || !adaptiveHeightEnabled || mode == PresentationDensityMode.compatibility) {
      return legacyHeight;
    }

    final ratio = sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? sourceAspectRatio : 9 / 16;
    final desiredHeight = availableWidth / ratio;
    final reservedDanmaku = mode == PresentationDensityMode.immersive ? 120.0 : minimumDanmakuHeight;
    final fractionCap = availableHeight * (mode == PresentationDensityMode.immersive ? 0.78 : 0.60);
    final panelCap = availableHeight - resolutionHeight - reservedDanmaku;
    final upperBound = math.max(legacyHeight, math.min(fractionCap, panelCap));
    return desiredHeight.clamp(legacyHeight, upperBound);
  }

  /// Returns the ratio used by a compact window — system picture-in-picture on
  /// mobile, the always-on-top small window on desktop.
  ///
  /// Portrait adaptation is an opt-in extension to the established 16:9
  /// landscape pipeline. Landscape, square, unknown and implausible metadata
  /// therefore keep the legacy ratio instead of allowing one decoder metadata
  /// anomaly to resize every presentation mode.
  static double resolveCompactWindowAspectRatio({
    required VideoGeometrySnapshot snapshot,
    required VideoOrientationKind effectiveOrientation,
    required bool followStablePortraitSource,
  }) {
    if (effectiveOrientation != VideoOrientationKind.portrait) return 16 / 9;
    if (!snapshot.isStable || !followStablePortraitSource) return 9 / 16;
    return resolveVideoDisplayAspectRatio(snapshot: snapshot, effectiveOrientation: effectiveOrientation);
  }

  /// Android accepts PiP ratios only in the inclusive [1/2.39, 2.39] range.
  /// Invalid decoder dimensions fall back to the effective presentation ratio.
  static PipAspectRatio resolveAndroidPipAspectRatio({
    required int width,
    required int height,
    required bool portraitFallback,
  }) {
    var ratio = width > 0 && height > 0 ? width / height : (portraitFallback ? 9 / 16 : 16 / 9);
    ratio = ratio.clamp(androidPipMinimumAspectRatio, androidPipMaximumAspectRatio);
    const denominator = 1000;
    final minimumNumerator = (androidPipMinimumAspectRatio * denominator).ceil();
    final maximumNumerator = (androidPipMaximumAspectRatio * denominator).floor();
    final numerator = (ratio * denominator).round().clamp(minimumNumerator, maximumNumerator);
    final divisor = _greatestCommonDivisor(numerator, denominator);
    return PipAspectRatio(numerator ~/ divisor, denominator ~/ divisor);
  }

  static int _greatestCommonDivisor(int a, int b) {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
      final remainder = x % y;
      x = y;
      y = remainder;
    }
    return x == 0 ? 1 : x;
  }
}

/// Enforces the geometry contract at the renderer boundary. A stale or
/// malformed crop is ignored when its resulting viewport disagrees with the
/// already resolved presentation ratio.
NormalizedVideoInsets resolveConsistentVideoContentInsets({
  required double encodedAspectRatio,
  required double presentationAspectRatio,
  required NormalizedVideoInsets contentInsets,
}) {
  if (!contentInsets.hasCrop ||
      !contentInsets.isValid ||
      !encodedAspectRatio.isFinite ||
      encodedAspectRatio <= 0 ||
      !presentationAspectRatio.isFinite ||
      presentationAspectRatio <= 0) {
    return NormalizedVideoInsets.none;
  }
  final croppedRatio = contentInsets.applyToAspectRatio(encodedAspectRatio);
  if (_relativeRatioDifference(croppedRatio, presentationAspectRatio) > 0.08) {
    return NormalizedVideoInsets.none;
  }
  return contentInsets;
}
