import 'package:freezed_annotation/freezed_annotation.dart';

part 'source_metadata.freezed.dart';

/// Additional metadata attached to a media source.
///
/// [SourceMetadata] contains optional descriptive
/// information about a source.
///
/// Examples:
///
/// - title
/// - artist
/// - channel name
/// - language
/// - custom tags
///
/// Responsibilities:
///
/// - store source metadata
/// - provide immutable metadata object
///
/// It does not:
///
/// - inspect media streams
/// - extract codec information
/// - probe network resources
///
/// Those belong to:
///
/// - SourceInspector
@freezed
abstract class SourceMetadata with _$SourceMetadata {
  /// Creates source metadata.
  const factory SourceMetadata({
    /// Display title.
    String? title,

    /// Description text.
    String? description,

    /// Author or creator.
    String? author,

    /// Channel name.
    String? channel,

    /// Language code.
    ///
    /// Example:
    /// - en
    /// - zh-CN
    String? language,

    /// Thumbnail or poster URL.
    Uri? artwork,

    /// Duration in milliseconds.
    Duration? duration,

    /// Additional custom metadata.
    @Default({}) Map<String, Object?> extras,
  }) = _SourceMetadata;

  /// Creates empty metadata.
  factory SourceMetadata.empty() {
    return const SourceMetadata();
  }
}

/// Extensions for [SourceMetadata].
extension SourceMetadataExtension on SourceMetadata {
  /// Whether metadata contains no values.
  bool get isEmpty {
    return title == null &&
        description == null &&
        author == null &&
        channel == null &&
        language == null &&
        artwork == null &&
        duration == null &&
        extras.isEmpty;
  }

  /// Whether metadata has any value.
  bool get isNotEmpty {
    return !isEmpty;
  }

  /// Whether artwork exists.
  bool get hasArtwork {
    return artwork != null;
  }

  /// Whether duration exists.
  bool get hasDuration {
    return duration != null;
  }

  /// Returns metadata value by key.
  Object? operator [](String key) {
    return extras[key];
  }

  /// Creates metadata with an extra field.
  SourceMetadata putExtra(String key, Object? value) {
    return copyWith(extras: {...extras, key: value});
  }

  /// Removes an extra field.
  SourceMetadata removeExtra(String key) {
    final values = Map<String, Object?>.from(extras)..remove(key);

    return copyWith(extras: values);
  }
}
