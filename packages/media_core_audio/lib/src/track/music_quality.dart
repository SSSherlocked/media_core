import 'package:flutter/foundation.dart' show immutable;

/// Audio quality tier of a music source.
///
/// Mirrors the tiers lx-music exposes (128k / 320k / flac / flac24bit /
/// hires): the value is a *request*, and the concrete bitrate/format stays
/// the source's business. [id] is what a source implementation keys off, so
/// it is deliberately a string rather than an enum — sources differ in what
/// they can serve, and an app-specific tier must not require editing the
/// framework.
@immutable
final class MusicQuality {
  /// Creates a quality tier.
  const MusicQuality({required this.id, required this.label, this.bitrateKbps, this.formatHint, this.sort = 0});

  /// Stable identifier a source implementation understands.
  final String id;

  /// Human-readable label, for the host's menus.
  final String label;

  /// Nominal bitrate, when known.
  final int? bitrateKbps;

  /// Container/extension hint (`flac`, `mp3`, `m4a`), when known.
  final String? formatHint;

  /// Ordering weight; higher is better.
  final int sort;

  /// Let the source pick the best tier it can serve.
  static const MusicQuality auto = MusicQuality(id: 'auto', label: '自动', sort: -1);

  /// 128 kbps.
  static const MusicQuality k128 = MusicQuality(id: '128k', label: '128K', bitrateKbps: 128, formatHint: 'mp3');

  /// 192 kbps.
  static const MusicQuality k192 = MusicQuality(
    id: '192k',
    label: '192K',
    bitrateKbps: 192,
    formatHint: 'mp3',
    sort: 1,
  );

  /// 320 kbps.
  static const MusicQuality k320 = MusicQuality(
    id: '320k',
    label: '320K',
    bitrateKbps: 320,
    formatHint: 'mp3',
    sort: 2,
  );

  /// CD-quality lossless.
  static const MusicQuality flac = MusicQuality(id: 'flac', label: 'FLAC', formatHint: 'flac', sort: 3);

  /// 24-bit lossless.
  static const MusicQuality flac24bit = MusicQuality(id: 'flac24bit', label: 'FLAC 24bit', formatHint: 'flac', sort: 4);

  /// High-resolution lossless.
  static const MusicQuality hires = MusicQuality(id: 'hires', label: 'Hi-Res', formatHint: 'flac', sort: 5);

  /// The tiers every source may be asked for, best last.
  static const List<MusicQuality> all = <MusicQuality>[k128, k192, k320, flac, flac24bit, hires];

  /// Whether this tier is [auto].
  bool get isAuto => id == auto.id;

  @override
  bool operator ==(Object other) => other is MusicQuality && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MusicQuality($id)';
}
