/// Why an upstream cannot be handed to the native player as it is.
///
/// A host reports what it knows about the source; the plan then says how the
/// input has to be delivered. Keeping the decision here stops every host from
/// re-deriving the same three-way branch in its own playback transport.
enum IngestNeed {
  /// The manifest lists children as bare names (`media.95.mp4`). A native
  /// resolver that loses the manifest URL turns those into local paths, so the
  /// children must be re-pointed at absolute URLs first.
  relativeChildren,

  /// The child URIs are absolute paths (`/tc.livehls/...`) that a native
  /// resolver may read as a file path when the base URL is not authoritative.
  absolutePathChildren,

  /// The signed URL expires while the stream is still playing, so the input has
  /// to survive a URL swap underneath one continuous stream.
  expiringUrl,

  /// The container or codec is outside what the player's FFmpeg can parse (for
  /// example codec-id-12 HEVC FLV).
  legacyContainer,

  /// The manifest's token parameter must be replayed on every child request.
  childToken,

  /// The provider hands out cookies with the manifest that its children inherit.
  sessionCookies,
}

/// How an input reaches the player.
enum IngestStrategy {
  /// Hand the URL (and headers) straight to the player.
  direct,

  /// Serve a rewritten manifest tree from loopback HTTP; the player only ever
  /// sees absolute `http://127.0.0.1:<port>/...` URLs.
  manifestRelay,

  /// Remux with FFmpeg into a loopback HLS tree the player can parse.
  ffmpegRelay,
}

/// The resolved delivery decision for one source.
final class IngestPlan {
  /// A plan that hands the source to the player unchanged.
  const IngestPlan.direct() : strategy = IngestStrategy.direct, needs = const <IngestNeed>{};

  const IngestPlan._(this.strategy, this.needs);

  /// The delivery strategy chosen for the source.
  final IngestStrategy strategy;

  /// What the relay has to do before the source is playable.
  final Set<IngestNeed> needs;

  /// Whether this plan plays the source directly, with no relay work.
  bool get isDirect => strategy == IngestStrategy.direct;

  @override
  String toString() =>
      'IngestPlan(${strategy.name}${needs.isEmpty ? '' : ': ${needs.map((need) => need.name).join(', ')}'})';
}

/// Whether [uri] addresses an HLS playlist, including the suffix-less variants
/// some providers use (`/playlist`, `/master_playlist`).
bool isHlsManifestUri(Uri uri) => _manifestPath.hasMatch(uri.path);

final RegExp _manifestPath = RegExp(r'(\.m3u8|/(master_)?playlist)$', caseSensitive: false);

/// Source kinds that are already playable as-is; everything else needs a reason.
///
/// FFmpeg relaying costs a process, a port and one to three seconds of startup,
/// so a plain HLS/FLV source must stay on the direct path. Only a declared need
/// moves it.
IngestPlan resolveIngestPlan({required Set<IngestNeed> needs, bool sourceIsManifest = true}) {
  if (needs.isEmpty) return const IngestPlan.direct();
  if (needs.contains(IngestNeed.legacyContainer) || needs.contains(IngestNeed.expiringUrl)) {
    return IngestPlan._(IngestStrategy.ffmpegRelay, Set<IngestNeed>.unmodifiable(needs));
  }
  if (!sourceIsManifest) return const IngestPlan.direct();
  return IngestPlan._(IngestStrategy.manifestRelay, Set<IngestNeed>.unmodifiable(needs));
}
