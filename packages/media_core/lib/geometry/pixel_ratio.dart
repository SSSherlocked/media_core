import 'package:equatable/equatable.dart';

/// Device pixel ratio value.
///
/// Represents physical pixel density.
///
/// Examples:
///
/// 1.0  -> normal display
/// 2.0  -> retina/high density
/// 3.0  -> xxhdpi
///
/// This class only describes density.
///
/// Does not:
///
/// - resize widgets
/// - scale video pixels
/// - control renderer
final class PixelRatioValue extends Equatable {
  /// Creates a pixel ratio from a raw density value.
  const PixelRatioValue(this.value);

  /// Restores a pixel ratio from a map produced by [toMap].
  ///
  /// Falls back to density 1.0 when the map carries no usable value.
  factory PixelRatioValue.fromMap(Map<String, dynamic> map) {
    return PixelRatioValue((map['value'] as num?)?.toDouble() ?? 1.0);
  }

  /// Default pixel ratio.
  const PixelRatioValue.one() : value = 1.0;

  /// Empty pixel ratio.
  const PixelRatioValue.zero() : value = 0;

  /// Creates from device pixel ratio.
  factory PixelRatioValue.fromDevicePixelRatio(double ratio) {
    if (!ratio.isFinite || ratio <= 0) {
      return const PixelRatioValue.one();
    }

    return PixelRatioValue(ratio);
  }

  /// Raw value.
  final double value;

  /// Whether ratio is valid.
  bool get isValid {
    return value.isFinite && value > 0;
  }

  /// Whether high density display.
  bool get isHighDensity {
    return value > 1.0;
  }

  /// Whether retina density.
  bool get isRetina {
    return value >= 2.0;
  }

  /// Converts logical pixels to physical pixels.
  double toPhysical(double logicalPixels) {
    if (!isValid || logicalPixels <= 0) {
      return 0;
    }

    return logicalPixels * value;
  }

  /// Converts physical pixels to logical pixels.
  double toLogical(double physicalPixels) {
    if (!isValid || physicalPixels <= 0) {
      return 0;
    }

    return physicalPixels / value;
  }

  /// Scales another size value.
  double scale(double pixels) {
    if (!isValid) {
      return pixels;
    }

    return pixels * value;
  }

  /// Creates rounded value.
  PixelRatioValue round([int decimals = 2]) {
    final factor = _pow10(decimals);

    return PixelRatioValue((value * factor).round() / factor);
  }

  /// Creates copy.
  PixelRatioValue copyWith(double value) {
    return PixelRatioValue(value);
  }

  /// Converts to a simple map.
  Map<String, dynamic> toMap() {
    return {'value': value};
  }

  static double _pow10(int value) {
    var result = 1.0;

    for (var i = 0; i < value; i++) {
      result *= 10;
    }

    return result;
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() {
    return 'PixelRatioValue($value)';
  }
}
