import 'package:equatable/equatable.dart';

/// Runtime visibility state.
final class VisibilityState extends Equatable {
  /// Creates visibility state from explicit values.
  const VisibilityState({this.visible = false, this.visibility = 0.0, this.inViewport = false, this.occluded = false});

  /// Whether widget is visible.
  final bool visible;

  /// Visibility ratio.
  ///
  /// Range:
  ///
  /// 0.0 - 1.0
  final double visibility;

  /// Whether player is inside viewport.
  final bool inViewport;

  /// Whether player is covered.
  final bool occluded;

  /// Whether the whole player is on screen.
  bool get isFullyVisible {
    return visibility >= 1.0;
  }

  /// Whether only part of the player is on screen.
  bool get isPartiallyVisible {
    return visibility > 0 && visibility < 1;
  }

  /// Whether none of the player is on screen.
  bool get isHidden {
    return visibility <= 0;
  }

  /// Creates a copy with the supplied values replaced.
  VisibilityState copyWith({bool? visible, double? visibility, bool? inViewport, bool? occluded}) {
    return VisibilityState(
      visible: visible ?? this.visible,
      visibility: visibility ?? this.visibility,
      inViewport: inViewport ?? this.inViewport,
      occluded: occluded ?? this.occluded,
    );
  }

  /// Applies a new visibility [value], treating any positive ratio as visible.
  VisibilityState update(double value) {
    return copyWith(visibility: value, visible: value > 0);
  }

  /// Marks the player visible without touching the ratio.
  VisibilityState show() {
    return copyWith(visible: true);
  }

  /// Marks the player hidden and zeroes the ratio.
  VisibilityState hide() {
    return copyWith(visible: false, visibility: 0);
  }

  @override
  List<Object?> get props => [visible, visibility, inViewport, occluded];
}
