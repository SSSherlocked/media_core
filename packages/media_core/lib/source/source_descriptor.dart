import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_headers.dart';
import 'package:media_core/source/source_location.dart';
import 'package:media_core/source/source_media_type.dart';
import 'package:media_core/source/source_metadata.dart';
import 'package:media_core/source/source_protocol.dart';
import 'package:media_core/source/source_type.dart';

part 'source_descriptor.freezed.dart';

/// Complete description of a media source.
///
/// [SourceDescriptor] contains all known information
/// about a media source before playback starts.
///
/// It is used between:
///
/// - source resolver
/// - player session
/// - adapter selection
///
/// Responsibilities:
///
/// - describe source identity
/// - describe access information
/// - describe media characteristics
///
/// It does not:
///
/// - open streams
/// - probe media
/// - create players
///
/// Those belong to:
///
/// - SourceResolver
/// - SourceInspector
/// - PlayerAdapter
@freezed
abstract class SourceDescriptor with _$SourceDescriptor {
  /// Creates a source descriptor.
  const factory SourceDescriptor({
    /// Unique source identifier.
    required SourceId id,

    /// Source location.
    required SourceLocation location,

    /// Source category.
    @Default(SourceType.unknown) SourceType type,

    /// Transport protocol.
    @Default(SourceProtocol.unknown) SourceProtocol protocol,

    /// Media content type.
    @Default(SourceMediaType.unknown) SourceMediaType mediaType,

    /// Container format.
    @Default(SourceFormat.unknown) SourceFormat format,

    /// Request headers.
    SourceHeaders? headers,

    /// Source metadata.
    SourceMetadata? metadata,

    /// Whether source is live.
    @Default(false) bool live,

    /// Whether seeking is supported.
    @Default(false) bool seekable,

    /// Optional priority.
    ///
    /// Higher value means preferred source.
    @Default(0) int priority,

    /// Custom attributes.
    @Default({}) Map<String, Object?> attributes,
  }) = _SourceDescriptor;

  /// Creates an empty descriptor.
  factory SourceDescriptor.empty() {
    return SourceDescriptor(id: SourceId.unknown(), location: SourceLocation.empty());
  }
}

/// Extensions for [SourceDescriptor].
extension SourceDescriptorExtension on SourceDescriptor {
  /// Whether source is valid enough for playback.
  bool get isValid {
    return location.isValid;
  }

  /// Whether source has request headers.
  bool get hasHeaders {
    return headers != null && headers!.isNotEmpty;
  }

  /// Whether source has metadata.
  bool get hasMetadata {
    return metadata != null && metadata!.isNotEmpty;
  }

  /// Whether source uses network access.
  bool get isNetwork {
    return protocol.isNetwork;
  }

  /// Creates descriptor with updated priority.
  SourceDescriptor withPriority(int value) {
    return copyWith(priority: value);
  }

  /// Creates descriptor with extra attribute.
  SourceDescriptor putAttribute(String key, Object? value) {
    return copyWith(attributes: {...attributes, key: value});
  }
}
