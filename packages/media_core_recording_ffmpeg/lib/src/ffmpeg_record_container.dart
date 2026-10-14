/// The container a recording is written into.
///
/// Two are offered, and only two, because a live recording has no reliable end:
/// the container has to be playable per segment and survive being killed mid
/// write. A plain MP4 is excluded for that reason (its `moov` index is written at
/// the end, so a killed process leaves an unusable file), and Matroska is
/// excluded because a crash mid-cluster leaves a file whose duration lies.
enum FfmpegRecordContainer {
  /// Segmented MPEG-TS: every segment is a self-contained stream, and joining
  /// them is a byte copy (`-f concat` with the segment list, or plain
  /// concatenation, since TS packets carry their own timing).
  ///
  /// This is the default because it is the container a live capture is least
  /// likely to lose data in, at the cost of a container a normal player opens
  /// less happily and a slightly larger file (188-byte packet framing).
  mpegTs,

  /// Fragmented MP4: `empty_moov` writes a header with no sample table, and each
  /// fragment then carries its own `moof`+`mdat`, so a segment that was never
  /// closed properly is still readable up to the last complete fragment.
  ///
  /// Chosen when the host wants a file every platform player accepts. Joining
  /// fragments is NOT a byte copy: a fragmented MP4 has to be re-wrapped, which
  /// is what the post-recording remux step does.
  mp4Fragmented,
}

/// How FFmpeg is told to write each container.
extension FfmpegRecordContainerFormat on FfmpegRecordContainer {
  /// Segment file name suffix that names the profile it was written under.
  ///
  /// The profile is in the name so a recording from older clock semantics is
  /// never mistaken for this one and merged with it.
  String get segmentSuffix => switch (this) {
    FfmpegRecordContainer.mpegTs => '.clock-v1.ts',
    FfmpegRecordContainer.mp4Fragmented => '.clock-v1.mp4',
  };

  /// FFmpeg's `-segment_format` value.
  String get segmentFormat => switch (this) {
    FfmpegRecordContainer.mpegTs => 'mpegts',
    FfmpegRecordContainer.mp4Fragmented => 'mp4',
  };

  /// FFmpeg's `-segment_format_options` value, applied to each child file.
  ///
  /// MPEG-TS commits complete packets as they are written (`flush_packets=1`)
  /// rather than leaving a partial 512 KiB AVIO prefix when cancellation prevents
  /// the trailer from flushing. Only the outer muxer normalises the clock: a
  /// second per-child shift breaks reconstruction from the segment list's
  /// reference timestamps, so child delay is zero and the 1.4 s offset keeps
  /// MPEG-TS's former preroll — without it, concat's inpoint 0 discards leading
  /// negative DTS in later segments.
  ///
  /// Fragmented MP4 instead asks for one fragment per key frame and an empty
  /// movie header, with `default_base_moof` so the fragments describe themselves
  /// and a later re-wrap can read them.
  String get segmentFormatOptions => switch (this) {
    FfmpegRecordContainer.mpegTs => 'flush_packets=1:avoid_negative_ts=disabled:max_delay=0:output_ts_offset=1.4',
    FfmpegRecordContainer.mp4Fragmented => 'movflags=frag_keyframe+empty_moov+default_base_moof',
  };

  /// Whether segments join by a byte copy rather than by a re-wrap.
  bool get isConcatenateByCopy => this == FfmpegRecordContainer.mpegTs;
}
