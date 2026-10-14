import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/source_headers.dart';
import 'package:media_core/source/source_type.dart';

part 'source_request.freezed.dart';

/// Represents a request to load a media source.
///
/// [SourceRequest] is the input model passed to
/// source resolving and playback preparation.
///
/// Responsibilities:
///
/// - identify requested source
/// - provide request options
/// - carry loading preferences
///
/// It does not:
///
/// - resolve URLs
/// - open network connections
/// - create players
///
/// Those belong to:
///
/// - SourceResolver
/// - PlayerSession
/// - PlayerAdapter
@freezed
abstract class SourceRequest with _$SourceRequest {
  /// Creates a source request.
  const factory SourceRequest({
    /// Request identifier.
    required RequestId id,

    /// Target source identifier.
    SourceId? sourceId,

    /// Source URI.
    Uri? uri,

    /// Preferred source type.
    @Default(SourceType.unknown) SourceType type,

    /// Additional request headers.
    SourceHeaders? headers,

    /// Whether this request is for live playback.
    @Default(false) bool live,

    /// Whether to prefer low latency.
    @Default(false) bool lowLatency,

    /// Whether caching should be enabled.
    @Default(true) bool enableCache,

    /// Whether network fallback is allowed.
    @Default(true) bool allowFallback,

    /// Optional timeout.
    Duration? timeout,

    /// Custom request attributes.
    @Default({}) Map<String, Object?> attributes,
  }) = _SourceRequest;

  /// Creates a request from URI.
  factory SourceRequest.fromUri(Uri uri) {
    return SourceRequest(id: RequestId.generate(), uri: uri);
  }
}

/// Extensions for [SourceRequest].
extension SourceRequestExtension on SourceRequest {
  /// Whether request has a URI.
  bool get hasUri {
    return uri != null;
  }

  /// Whether request has source id.
  bool get hasSourceId {
    return sourceId != null;
  }

  /// Whether request can be resolved.
  bool get resolvable {
    return hasUri || hasSourceId;
  }

  /// Whether this is a live request.
  bool get isLive {
    return live;
  }

  /// Creates request with attribute.
  SourceRequest putAttribute(String key, Object? value) {
    return copyWith(attributes: {...attributes, key: value});
  }
}
