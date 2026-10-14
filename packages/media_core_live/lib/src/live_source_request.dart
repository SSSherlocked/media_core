import 'package:media_core/media_core.dart';

/// One live playback request: the sources to try, in order.
///
/// Callers hand over wrapped [PlayerSource]s — the type the whole framework
/// scores and opens against. Protocol, format, headers and identity are
/// declared by the caller on each source, because those are exactly the
/// fields backend selection reads.
///
/// [LiveSourceRequest.fromUrls] is the exception, and it is labelled as one:
/// most live-site APIs hand over strings and nothing else, so it wraps them —
/// but it can only *infer* protocol and format from the scheme and extension.
/// A caller that knows better than inference should build [sources] directly.
///
/// Recovery scope is declared here as well. The number of sources decides
/// how much *line* fallback there is — and nothing else:
///
/// - Multiple sources: sweep every line on the current engine, then move
///   to the next engine and sweep again, until something plays.
/// - A single source: there is no other line, so the sweep is one engine,
///   one line — but the next engine still gets its turn on the same URL.
///
/// In both shapes the failure is reported to the caller only after every
/// allowed engine has been tried. Pass `allowEngineFallback: false` to
/// refuse engine escalation entirely and have the first failure surface.
final class LiveSourceRequest {
  /// Declares the candidate lines to sweep, in the order the caller prefers.
  ///
  /// The list is copied into an unmodifiable one, so the sweep cannot see a
  /// caller mutating it mid-fallback.
  LiveSourceRequest({required List<PlayerSource> sources, this.title, this.allowEngineFallback})
    : sources = List<PlayerSource>.unmodifiable(sources);

  /// Wraps raw URLs into sources, applying [headers] to every line.
  ///
  /// Convenience for callers that only hold strings (most live-site APIs).
  /// Protocol and format are inferred from each URL's scheme and extension;
  /// pass [sources] instead when the caller knows better than inference.
  factory LiveSourceRequest.fromUrls(
    List<String> urls, {
    Map<String, String> headers = const <String, String>{},
    String? title,
    bool? allowEngineFallback,
  }) {
    return LiveSourceRequest(
      sources: urls
          .map((url) {
            final uri = Uri.parse(url);

            return PlayerSource(
              id: SourceId('live_${uri.host}${uri.path.hashCode}'),
              uri: uri,
              type: SourceType.live,
              protocol: SourceProtocol.fromScheme(uri.scheme),
              format: SourceFormat.fromUri(uri),
              headers: headers.isEmpty ? null : SourceHeaders(headers),
              title: title,
            );
          })
          .toList(growable: false),
      title: title,
      allowEngineFallback: allowEngineFallback,
    );
  }

  /// Candidate sources, best first. [sources].first is opened first.
  final List<PlayerSource> sources;

  /// Optional display title for events.
  final String? title;

  /// Whether recovery may attach another engine after every source failed.
  ///
  /// `null` — the default — means automatic: allowed for multi-source
  /// requests, refused for a single-source request, whose failure is
  /// reported to the caller instead.
  final bool? allowEngineFallback;

  /// The source recovery starts from.
  PlayerSource get primary => sources.first;

  /// Whether this request carries more than one candidate.
  bool get hasAlternatives => sources.length > 1;

  @override
  String toString() {
    return 'LiveSourceRequest(${sources.length} source(s), primary: ${primary.uri}, title: $title)';
  }
}
