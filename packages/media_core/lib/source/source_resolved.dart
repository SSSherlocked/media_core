import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_headers.dart';
import 'package:media_core/source/source_media_type.dart';
import 'package:media_core/source/source_protocol.dart';

part 'source_resolved.freezed.dart';

/// Represents a source after source resolution.
///
/// [ResolvedSource] contains the concrete access information produced by a
/// source resolver. It is suitable for passing to an adapter or player
/// factory.
///
/// Resolution may normalize a URI, determine a protocol, merge request
/// headers, or otherwise transform the original [PlayerSource].
///
/// [ResolvedSource] does not:
///
/// - open the source
/// - inspect media streams
/// - create a player
/// - manage playback
/// - perform recovery or fallback
@freezed
abstract class ResolvedSource with _$ResolvedSource {
  /// Creates a resolved source.
  const factory ResolvedSource({
    /// Identifier of the original source.
    required SourceId sourceId,

    /// Concrete URI to be passed to the backend.
    required Uri uri,

    /// Resolved access protocol.
    @Default(SourceProtocol.unknown) SourceProtocol protocol,

    /// Resolved media type.
    @Default(SourceMediaType.unknown) SourceMediaType mediaType,

    /// Resolved media format.
    @Default(SourceFormat.unknown) SourceFormat format,

    /// Request headers required to access the resolved source.
    SourceHeaders? headers,

    /// Original source from which this resolved source was produced.
    PlayerSource? source,

    /// Additional resolver-specific metadata.
    @Default(<String, Object?>{}) Map<String, Object?> metadata,
  }) = _ResolvedSource;

  const ResolvedSource._();

  /// Whether this source has a non-empty URI.
  bool get hasUri {
    return uri.toString().trim().isNotEmpty;
  }

  /// Whether the source has a valid identifier.
  bool get hasSourceId {
    return sourceId != SourceId.unknown();
  }

  /// Whether request headers are present.
  bool get hasHeaders => headers != null && headers!.isNotEmpty;

  /// Whether resolver metadata is present.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Whether the source has been resolved sufficiently for an adapter.
  ///
  /// This only validates the resolved descriptor. It does not verify that
  /// the URI is reachable or that the backend can actually open it.
  bool get isValid {
    return hasSourceId && hasUri && protocol.isKnown;
  }

  /// Whether this is a network source.
  bool get isNetworkSource => protocol.isNetwork;

  /// Whether this is a local source.
  bool get isLocalSource => protocol.isLocal;

  /// Whether this is an HTTP-based source.
  bool get isHttpSource => protocol.isHttp;

  /// Whether this is an HLS source.
  bool get isHls => protocol.isHls;

  /// Whether this is a DASH source.
  bool get isDash => protocol.isDash;

  /// Whether this is a file source.
  bool get isFile => protocol.isFile;

  /// Whether this is an application asset.
  bool get isAsset => protocol.isAsset;

  /// Returns a metadata value.
  Object? metadataValue(String key) => metadata[key];

  /// Whether a metadata key exists.
  bool hasMetadataKey(String key) => metadata.containsKey(key);

  /// Returns a new resolved source with the specified header.
  ResolvedSource withHeader(String name, String value) {
    final current = headers ?? SourceHeaders.empty;

    return copyWith(headers: current.set(name, value));
  }

  /// Returns a new resolved source without the specified header.
  ResolvedSource withoutHeader(String name) {
    final current = headers;

    if (current == null) {
      return this;
    }

    return copyWith(headers: current.remove(name));
  }
}
