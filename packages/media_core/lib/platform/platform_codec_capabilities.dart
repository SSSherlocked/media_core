import 'package:equatable/equatable.dart';

/// Video codecs a platform's decoder list can be asked about.
///
/// The set is deliberately small and stable: it is the vocabulary a decode
/// decision needs, not a full MIME registry. Anything a probe reports that is
/// not in here is folded into [other] rather than dropped, so "the device
/// decodes *something* we do not name" stays visible.
enum VideoCodec {
  /// H.264 / AVC.
  h264,

  /// H.265 / HEVC.
  hevc,

  /// VP9.
  vp9,

  /// AV1.
  av1,

  /// MPEG-4 part 2.
  mpeg4,

  /// MPEG-2.
  mpeg2,

  /// VC-1.
  vc1,

  /// A codec the vocabulary does not name.
  other;

  /// Parses a codec name or MIME type.
  ///
  /// Accepts what engines report (`hevc`, `h265`, `video/hevc`,
  /// `hevc (Main 10)`, `avc1.640028`) because every one of those spellings
  /// shows up in a real track list, and a decoder that does not parse its own
  /// engine's spelling is worse than useless.
  static VideoCodec? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toLowerCase();

    if (normalized.contains('hevc') || normalized.contains('h265') || normalized.contains('h.265')) {
      return VideoCodec.hevc;
    }

    if (normalized.contains('avc') || normalized.contains('h264') || normalized.contains('h.264')) {
      return VideoCodec.h264;
    }

    if (normalized.contains('vp9') || normalized.contains('vp09')) {
      return VideoCodec.vp9;
    }

    if (normalized.contains('av1') || normalized.contains('av01')) {
      return VideoCodec.av1;
    }

    if (normalized.contains('mpeg4') || normalized.contains('mp4v')) {
      return VideoCodec.mpeg4;
    }

    if (normalized.contains('mpeg2') || normalized.contains('mp2v')) {
      return VideoCodec.mpeg2;
    }

    if (normalized.contains('vc1') || normalized.contains('vc-1')) {
      return VideoCodec.vc1;
    }

    return null;
  }

  /// Whether the codec is efficient enough that software decoding is a real
  /// fallback cost rather than a rounding error.
  ///
  /// This is the difference between "let the decoder sort it out" and "a
  /// 1080p HEVC stream will not decode in software on a TV box".
  bool get isHeavyWithoutHardware {
    return this == VideoCodec.hevc || this == VideoCodec.av1 || this == VideoCodec.vp9;
  }
}

/// What a platform can do with one video codec.
final class CodecDecodeSupport extends Equatable {
  /// Creates a codec support record.
  const CodecDecodeSupport({
    required this.codec,
    required this.hardware,
    this.maxWidth = 0,
    this.maxHeight = 0,
    this.maxFrameRate = 0,
  });

  /// Creates a record from a map.
  factory CodecDecodeSupport.fromMap(VideoCodec codec, Map<String, Object?> map) {
    return CodecDecodeSupport(
      codec: codec,
      hardware: map['hardware'] as bool? ?? false,
      maxWidth: (map['maxWidth'] as num?)?.toInt() ?? 0,
      maxHeight: (map['maxHeight'] as num?)?.toInt() ?? 0,
      maxFrameRate: (map['maxFrameRate'] as num?)?.toInt() ?? 0,
    );
  }

  /// A codec the platform cannot decode in hardware.
  const CodecDecodeSupport.software(this.codec) : hardware = false, maxWidth = 0, maxHeight = 0, maxFrameRate = 0;

  /// Codec this record describes.
  final VideoCodec codec;

  /// Whether the platform exposes a hardware decoder for it.
  ///
  /// The fact that matters most: it is a property of the device, not of the
  /// stream, and it is what decides whether a hardware attempt is worth making
  /// at all.
  final bool hardware;

  /// Largest width the hardware decoder accepts; `0` when the platform does
  /// not report limits (Windows enumerates decoders but not their size caps).
  final int maxWidth;

  /// Largest height the hardware decoder accepts; `0` when unknown.
  final int maxHeight;

  /// Highest frame rate the hardware decoder accepts; `0` when unknown.
  final int maxFrameRate;

  /// Whether the platform reported resolution limits.
  bool get hasSizeLimits => maxWidth > 0 && maxHeight > 0;

  /// Whether this codec can be hardware-decoded at [width]x[height].
  ///
  /// A codec with no hardware decoder is refused outright. A codec *with* one
  /// is accepted when the size is unknown — the fact that a decoder exists is
  /// what the probe knows, and refusing on missing detail would turn "we do not
  /// know the limit" into "the limit is zero", which is the exact mistake this
  /// whole layer exists to avoid.
  bool supportsResolution({required int width, required int height}) {
    if (!hardware) {
      return false;
    }

    if (!hasSizeLimits || width <= 0 || height <= 0) {
      return true;
    }

    return width <= maxWidth && height <= maxHeight;
  }

  /// Creates a modified record.
  CodecDecodeSupport copyWith({bool? hardware, int? maxWidth, int? maxHeight, int? maxFrameRate}) {
    return CodecDecodeSupport(
      codec: codec,
      hardware: hardware ?? this.hardware,
      maxWidth: maxWidth ?? this.maxWidth,
      maxHeight: maxHeight ?? this.maxHeight,
      maxFrameRate: maxFrameRate ?? this.maxFrameRate,
    );
  }

  /// Debug serialization.
  Map<String, Object?> toMap() {
    return {
      'codec': codec.name,
      'hardware': hardware,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'maxFrameRate': maxFrameRate,
    };
  }

  @override
  List<Object?> get props => [codec, hardware, maxWidth, maxHeight, maxFrameRate];

  @override
  String toString() {
    return 'CodecDecodeSupport(${codec.name}: hardware=$hardware'
        '${hasSizeLimits ? ', max=${maxWidth}x$maxHeight' : ''}'
        '${maxFrameRate > 0 ? ', maxFps=$maxFrameRate' : ''})';
  }
}

/// What a platform can decode, and in hardware or not.
///
/// This is the answer to the question `PlayerAdapterCapabilities` cannot
/// answer: an adapter says "I can decode HEVC", while the *device* decides
/// whether that happens on a dedicated block or on four slow cores. Engines
/// that guess wrong spend the difference as a visible stall and a decoder
/// re-init, which is why the platform gets asked once and the answer is
/// carried into every session.
///
/// Responsibilities:
///
/// - carry the per-codec hardware answers
/// - answer "can this be hardware-decoded" for a codec and a resolution
///
/// It does not:
///
/// - choose a decoder (the adapter does, from this plus the device profile)
/// - query native APIs (PlatformProvider does)
///
/// ### Unknown is not unsupported
///
/// [PlatformCodecCapabilities.unknown] reports [reported] `false` and answers
/// every query with null rather than `false`, so a caller can tell "the
/// platform said no" apart from "nobody asked". A caller that treats silence as
/// "no hardware" would strip hardware decoding from every device whose probe
/// failed — the opposite of the intent.
final class PlatformCodecCapabilities extends Equatable {
  /// Creates codec capabilities.
  const PlatformCodecCapabilities({this.video = const <VideoCodec, CodecDecodeSupport>{}, this.reported = false});

  /// Creates capabilities from a map.
  factory PlatformCodecCapabilities.fromMap(Map<String, Object?> map) {
    final raw = map['video'];
    final video = <VideoCodec, CodecDecodeSupport>{};

    if (raw is Map) {
      for (final entry in raw.entries) {
        final codec = VideoCodec.tryParse(entry.key.toString());
        final value = entry.value;

        if (codec == null || value is! Map) {
          continue;
        }

        video[codec] = CodecDecodeSupport.fromMap(codec, value.map((key, item) => MapEntry(key.toString(), item)));
      }
    }

    return PlatformCodecCapabilities(video: video, reported: map['reported'] as bool? ?? video.isNotEmpty);
  }

  /// The capabilities of a platform nobody probed.
  static const PlatformCodecCapabilities unknown = PlatformCodecCapabilities();

  /// Per-codec support.
  final Map<VideoCodec, CodecDecodeSupport> video;

  /// Whether these answers came from a probe.
  final bool reported;

  /// Whether the answers are known.
  bool get isKnown => reported;

  /// Whether any codec was reported at all.
  bool get isEmpty => video.isEmpty;

  /// Support record for [codec], if the platform reported one.
  CodecDecodeSupport? operator [](VideoCodec codec) => video[codec];

  /// Codecs the platform can hardware-decode.
  Set<VideoCodec> get hardwareCodecs {
    return video.entries.where((entry) => entry.value.hardware).map((entry) => entry.key).toSet();
  }

  /// Whether hardware decoding is available for anything at all.
  bool get hasAnyHardwareDecoder => hardwareCodecs.isNotEmpty;

  /// Whether [codec] can be hardware-decoded at [width]x[height].
  ///
  /// Returns null when the platform has no answer: either nothing was probed,
  /// or this codec was not in the report. Callers that must decide anyway
  /// should treat null as "try it": mpv's own software fallback and the
  /// recovery ladder both handle a failed hardware attempt, while refusing
  /// hardware that exists costs every stream on the device.
  bool? canDecodeInHardware(VideoCodec codec, {int width = 0, int height = 0}) {
    if (!reported) {
      return null;
    }

    final support = video[codec];

    if (support == null) {
      return null;
    }

    return support.supportsResolution(width: width, height: height);
  }

  /// Whether [codecName] can be hardware-decoded, parsing the codec first.
  bool? canDecodeCodecName(String? codecName, {int width = 0, int height = 0}) {
    final codec = VideoCodec.tryParse(codecName);

    if (codec == null) {
      return null;
    }

    return canDecodeInHardware(codec, width: width, height: height);
  }

  /// Creates modified capabilities.
  PlatformCodecCapabilities copyWith({Map<VideoCodec, CodecDecodeSupport>? video, bool? reported}) {
    return PlatformCodecCapabilities(video: video ?? this.video, reported: reported ?? this.reported);
  }

  /// Debug serialization.
  Map<String, Object?> toMap() {
    return {'reported': reported, 'video': video.map((codec, support) => MapEntry(codec.name, support.toMap()))};
  }

  @override
  List<Object?> get props => [reported, Map<VideoCodec, CodecDecodeSupport>.unmodifiable(video)];

  @override
  String toString() {
    return 'PlatformCodecCapabilities(reported: $reported, video: $video)';
  }
}
