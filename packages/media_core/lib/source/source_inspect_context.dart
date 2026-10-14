import 'package:media_core/identity/request_id.dart';
import 'package:media_core/source/source_headers.dart';

/// Context used when inspecting a resolved media source.
///
/// [SourceInspectContext] contains request-scoped information required by
/// source inspection. It does not contain player state or backend state.
class SourceInspectContext {
  /// Creates an inspection context.
  ///
  /// Every field is optional: an inspector that needs no request
  /// identity, headers or metadata can use [SourceInspectContext.empty].
  const SourceInspectContext({this.requestId, this.headers, this.metadata = const <String, Object?>{}});

  /// Optional identifier of the inspection request.
  final RequestId? requestId;

  /// Additional request headers used during inspection.
  final SourceHeaders? headers;

  /// Additional inspector-specific metadata.
  final Map<String, Object?> metadata;

  /// Empty inspection context.
  static const SourceInspectContext empty = SourceInspectContext();

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
  SourceInspectContext withHeaders(SourceHeaders value) {
    final current = headers;

    return SourceInspectContext(
      requestId: requestId,
      headers: current == null ? value : current.merge(value),
      metadata: metadata,
    );
  }

  /// Returns a new context with a metadata value.
  SourceInspectContext withMetadata(String key, Object? value) {
    return SourceInspectContext(
      requestId: requestId,
      headers: headers,
      metadata: <String, Object?>{...metadata, key: value},
    );
  }

  /// Returns a new context without a metadata value.
  SourceInspectContext withoutMetadata(String key) {
    if (!metadata.containsKey(key)) {
      return this;
    }

    final next = <String, Object?>{...metadata}..remove(key);

    return SourceInspectContext(requestId: requestId, headers: headers, metadata: next);
  }
}
