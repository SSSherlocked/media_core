import 'package:equatable/equatable.dart';
import 'package:media_core/geometry/video_size.dart';

/// Immutable aspect ratio value.
///
/// Represents the relationship between width and height.
///
/// Examples:
///
/// 1920x1080 -> 16:9
/// 1080x1920 -> 9:16
///
/// This class only describes a ratio.
///
/// It does not:
///
/// - perform layout
/// - resize video
/// - rotate video
/// - apply renderer constraints
final class AspectRatioValue extends Equatable {
  /// Creates an aspect ratio from a raw ratio value.
  const AspectRatioValue(this.value);

  /// Creates an aspect ratio from width and height.
  factory AspectRatioValue.fromSize(VideoSize size) {
    return AspectRatioValue.fromDimensions(size.width, size.height);
  }

  /// Creates an aspect ratio from dimensions.
  factory AspectRatioValue.fromDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      return const AspectRatioValue.zero();
    }

    return AspectRatioValue(width / height);
  }

  /// Creates from a simple map.
  factory AspectRatioValue.fromMap(Map<String, dynamic> map) {
    final value = (map['value'] as num?)?.toDouble();

    if (value == null) {
      return const AspectRatioValue.zero();
    }

    return AspectRatioValue(value);
  }

  /// Empty aspect ratio.
  ///
  /// Used when video geometry is not available yet.
  const AspectRatioValue.zero() : value = 0;

  /// Standard 16:9 ratio.
  static const AspectRatioValue landscape16x9 = AspectRatioValue(16 / 9);

  /// Standard 9:16 ratio.
  static const AspectRatioValue portrait9x16 = AspectRatioValue(9 / 16);

  /// Square ratio.
  static const AspectRatioValue square = AspectRatioValue(1);

  /// Raw ratio value.
  final double value;

  /// Whether the ratio is valid.
  bool get isValid {
    return value.isFinite && value > 0;
  }

  /// Whether the ratio is empty.
  bool get isEmpty {
    return !isValid;
  }

  /// Returns a safe ratio.
  ///
  /// Invalid values are replaced by the default 16:9 ratio.
  double get normalized {
    if (!isValid) {
      return landscape16x9.value;
    }

    return value;
  }

  /// Whether the ratio represents landscape content.
  bool get isLandscape {
    return isValid && value > 1;
  }

  /// Whether the ratio represents portrait content.
  bool get isPortrait {
    return isValid && value < 1;
  }

  /// Whether the ratio represents square content.
  bool get isSquare {
    return isValid && value == 1;
  }

  /// Whether the ratio represents a typical vertical video.
  bool get isVertical {
    return isValid && value < 1;
  }

  /// Whether the ratio represents an unusually wide video.
  bool get isUltraWide {
    return isValid && value > 2.0;
  }

  /// Returns the inverse ratio.
  ///
  /// Example:
  ///
  /// 16:9 -> 9:16
  AspectRatioValue get inverted {
    if (!isValid) {
      return const AspectRatioValue.zero();
    }

    return AspectRatioValue(1 / value);
  }

  /// Returns a ratio constrained to the supplied range.
  ///
  /// This is useful for protecting UI layout from unreasonable
  /// source metadata.
  AspectRatioValue clamp({double min = 0.5, double max = 3.0}) {
    if (!min.isFinite || !max.isFinite || min <= 0 || max < min) {
      return this;
    }

    if (!isValid) {
      return const AspectRatioValue.zero();
    }

    return AspectRatioValue(value.clamp(min, max));
  }

  /// Calculates width for the supplied height.
  double widthForHeight(double height) {
    if (!isValid || height <= 0) {
      return 0;
    }

    return height * value;
  }

  /// Calculates height for the supplied width.
  double heightForWidth(double width) {
    if (!isValid || width <= 0) {
      return 0;
    }

    return width / value;
  }

  /// Creates a copy with a different value.
  AspectRatioValue copyWith(double value) {
    return AspectRatioValue(value);
  }

  /// Converts to a simple map.
  Map<String, double> toMap() {
    return {'value': value};
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() {
    return 'AspectRatioValue($value)';
  }
}
