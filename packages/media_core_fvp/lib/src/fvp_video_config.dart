import 'package:flutter/material.dart';

/// Viewport configuration for the surface built by the fvp adapter.
///
/// The adapter owns the texture; this describes how it is presented and how
/// large the render target may be.
@immutable
final class FvpVideoConfig {
  /// Creates a video configuration.
  const FvpVideoConfig({
    this.fit = BoxFit.contain,
    this.fill = const Color(0xFF000000),
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.maxWidth,
    this.maxHeight,
    this.fitMaxSize = true,
    this.tunnel = false,
  });

  /// How frames are inscribed into the allocated space.
  final BoxFit fit;

  /// Background color behind the video.
  final Color fill;

  /// Alignment of the video inside its viewport.
  final Alignment alignment;

  /// Texture sampling quality.
  final FilterQuality filterQuality;

  /// Upper bound for the render target width, in pixels.
  ///
  /// A 4K video in a 1080p UI otherwise allocates a full-resolution RGBA render
  /// target, which pushes weak TV GPUs into GPU composition. `null` keeps the
  /// decoded size.
  final int? maxWidth;

  /// Upper bound for the render target height, in pixels.
  final int? maxHeight;

  /// Whether [maxWidth]/[maxHeight] keep the video aspect ratio (the frame is
  /// scaled to fit inside the bound) instead of clamping each axis on its own.
  final bool fitMaxSize;

  /// Whether frames are handed to the platform surface directly.
  ///
  /// Tunnel mode skips libmdk's GL renderer, so the render-target clamp does
  /// not apply and the frame filters are unavailable.
  final bool tunnel;

  /// Copy with modifications.
  FvpVideoConfig copyWith({
    BoxFit? fit,
    Color? fill,
    Alignment? alignment,
    FilterQuality? filterQuality,
    int? maxWidth,
    int? maxHeight,
    bool? fitMaxSize,
    bool? tunnel,
  }) {
    return FvpVideoConfig(
      fit: fit ?? this.fit,
      fill: fill ?? this.fill,
      alignment: alignment ?? this.alignment,
      filterQuality: filterQuality ?? this.filterQuality,
      maxWidth: maxWidth ?? this.maxWidth,
      maxHeight: maxHeight ?? this.maxHeight,
      fitMaxSize: fitMaxSize ?? this.fitMaxSize,
      tunnel: tunnel ?? this.tunnel,
    );
  }
}
