import 'package:media_core/identity/request_id.dart';
import 'package:media_core/source/source_headers.dart';

/// Context used when resolving a media source.
///
/// [SourceResolveContext] contains request-scoped information needed during
/// source resolution. It does not contain player state or backend state.
class SourceResolveContext {
  /// Creates a resolve context.
  ///
  /// Every field is optional: a resolver that needs no request identity,
  /// headers or metadata can use [SourceResolveContext.empty].
  const SourceResolveContext({this.requestId, this.headers, this.metadata = const <String, Object?>{}});

  /// Optional identifier of the resolve request.
  final RequestId? requestId;

  /// Additional request headers supplied for this resolve operation.
  final SourceHeaders? headers;

  /// Additional resolver-specific metadata.
  final Map<String, Object?> metadata;

  /// Empty resolve context.
  static const SourceResolveContext empty = SourceResolveContext();

  /// Whether a request identifier is available.
  bool get hasRequestId => requestId != null;

  /// Whether additional headers are available.
  bool get hasHeaders => headers != null && headers!.isNotEmpty;

  /// Whether additional metadata is available.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Returns a metadata value.
  Object? metadataValue(String key) => metadata[key];

  /// Whether a metadata key exists.
  bool hasMetadataKey(String key) => metadata.containsKey(key);

  /// Returns a new context with merged headers.
  SourceResolveContext withHeaders(SourceHeaders value) {
    final current = headers;

    return SourceResolveContext(
      requestId: requestId,
      headers: current == null ? value : current.merge(value),
      metadata: metadata,
    );
  }

  /// Returns a new context with a metadata value.
  SourceResolveContext withMetadata(String key, Object? value) {
    return SourceResolveContext(
      requestId: requestId,
      headers: headers,
      metadata: <String, Object?>{...metadata, key: value},
    );
  }

  /// Returns a new context without a metadata value.
  SourceResolveContext withoutMetadata(String key) {
    if (!metadata.containsKey(key)) {
      return this;
    }

    final next = <String, Object?>{...metadata}..remove(key);

    return SourceResolveContext(requestId: requestId, headers: headers, metadata: next);
  }
}
