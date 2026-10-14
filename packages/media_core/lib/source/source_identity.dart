import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/source_id.dart';

part 'source_identity.freezed.dart';

/// Describes the identity information of a media source.
///
/// [SourceIdentity] provides source-level identity
/// information used during resolving and playback.
///
/// Difference from [SourceId]:
///
/// - SourceId:
///   global identifier used across modules.
///
/// - SourceIdentity:
///   descriptive identity information of a source.
///
/// Responsibilities:
///
/// - describe source identity
/// - store human-readable identifiers
///
/// It does not:
///
/// - generate identifiers
/// - manage lifecycle
/// - persist data
///
/// Those belong to:
///
/// - identity module
/// - storage layer
@freezed
abstract class SourceIdentity with _$SourceIdentity {
  /// Creates a source identity.
  const factory SourceIdentity({
    /// Global source identifier.
    required SourceId id,

    /// Provider identifier.
    ///
    /// Example:
    /// - youtube
    /// - bilibili
    /// - custom
    String? provider,

    /// External source identifier.
    ///
    /// Example:
    /// - channel id
    /// - room id
    /// - media id
    String? externalId,

    /// Human-readable name.
    String? name,

    /// Optional namespace.
    ///
    /// Example:
    /// - user
    /// - platform
    /// - service
    String? namespace,

    /// Additional identity attributes.
    @Default({}) Map<String, Object?> attributes,
  }) = _SourceIdentity;

  /// Creates an unknown identity.
  factory SourceIdentity.unknown() {
    return SourceIdentity(id: SourceId.unknown());
  }
}

/// Extensions for [SourceIdentity].
extension SourceIdentityExtension on SourceIdentity {
  /// Whether identity is known.
  bool get isKnown {
    return id != SourceId.unknown();
  }

  /// Whether external identity exists.
  bool get hasExternalId {
    return externalId != null && externalId!.isNotEmpty;
  }

  /// Whether provider exists.
  bool get hasProvider {
    return provider != null && provider!.isNotEmpty;
  }

  /// Creates identity with attribute.
  SourceIdentity putAttribute(String key, Object? value) {
    return copyWith(attributes: {...attributes, key: value});
  }
}
