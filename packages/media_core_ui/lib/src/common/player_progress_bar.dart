import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_core/media_core.dart';

import 'package:media_core_ui/src/common/player_control_buttons.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';

/// The timeline every control set shares.
///
/// One implementation of the interaction, themed by each design language: drag
/// to preview, release to seek, tap to jump, and a buffered range behind the
/// played range. Writing it once matters more than it sounds — "seek on every
/// drag update" floods an engine with commands and makes a drag stutter, and
/// every player that gets this wrong does so in the same place.
///
/// The look is tokenised rather than forked: [PlayerProgressThumb] decides
/// whether the played part ends in a cap (Cupertino), a full circle (Material,
/// Yaru, macOS) or a dot that grows under the pointer (Fluent), and
/// [PlayerProgressTrack.inset] sinks the groove into the surface for soft UI.
///
/// Responsibilities:
///
/// - own the drag-preview state
/// - seek once, on release
/// - paint track, buffered range, played range and thumb
///
/// It does not:
///
/// - decide colors or sizes ([PlayerControlsTheme] does)
/// - show times (bars do, driven by [onPreview])
final class PlayerProgressBar extends StatefulWidget {
  /// Creates a progress bar for [controller].
  const PlayerProgressBar({
    required this.controller,
    required this.theme,
    super.key,
    this.onPreview,
    this.height,
    this.thumbRadius,
    this.trackHeight,
    this.trackHeightWhileDragging,
    this.hoverable,
    this.padding = EdgeInsets.zero,
  });

  /// Controller whose player this bar seeks.
  final PlayerControlsController controller;

  /// Colors, metrics and shapes.
  final PlayerControlsTheme theme;

  /// Reports the position being previewed during a drag, and null when the drag
  /// ends.
  ///
  /// The bars use it to move their time labels, which is what makes a drag feel
  /// attached to the picture even before the engine catches up.
  final ValueChanged<Duration?>? onPreview;

  /// Height of the whole bar's hit area.
  final double? height;

  /// Radius of the thumb.
  final double? thumbRadius;

  /// Track height at rest.
  final double? trackHeight;

  /// Track height while dragging.
  final double? trackHeightWhileDragging;

  /// Whether the track thickens while the pointer is over it.
  final bool? hoverable;

  /// Padding around the track inside the hit area.
  final EdgeInsets padding;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

final class _PlayerProgressBarState extends State<PlayerProgressBar> {
  /// Fraction being previewed during a drag; null when not dragging.
  double? _dragFraction;

  bool _hovering = false;

  PlayerControlsTheme get _theme => widget.theme;

  bool get _hoverable => widget.hoverable ?? !_theme.progressThumbShape.isNone;

  bool get _growing => _dragFraction != null || (_hoverable && _hovering);

  double get _trackHeight {
    final base = widget.trackHeight ?? _theme.trackHeight;

    if (_growing) {
      return widget.trackHeightWhileDragging ?? _theme.trackHeightWhileDragging;
    }

    return base;
  }

  /// The engine's buffered stretches as track fractions.
  ///
  /// An empty list is the honest answer for three different cases a
  /// viewer cannot tell apart and should not be lied to about: the
  /// backend declared no range reporting, the clip has no duration
  /// (live), or nothing is buffered yet. All three paint no ahead
  /// fill, which is exactly what each of them means.
  List<_Fraction> _bufferedFractions(PlayerTransportState playback) {
    if (!playback.hasDuration) {
      return const <_Fraction>[];
    }

    final total = playback.duration.inMilliseconds;
    if (total <= 0) {
      return const <_Fraction>[];
    }

    return playback.buffer
        .normalize()
        .ranges
        .map(
          (range) => _Fraction(
            (range.start.inMilliseconds / total).clamp(0.0, 1.0),
            (range.end.inMilliseconds / total).clamp(0.0, 1.0),
          ),
        )
        .where((fraction) => !fraction.isEmpty)
        .toList(growable: false);
  }

  /// Track geometry for a pointer position inside the bar.
  double _fractionFor(Offset localPosition, double width) {
    if (width <= 0) {
      return 0;
    }

    return (localPosition.dx / width).clamp(0.0, 1.0);
  }

  Duration _positionFor(double fraction) {
    final duration = widget.controller.duration;

    if (duration <= Duration.zero) {
      return Duration.zero;
    }

    return Duration(microseconds: (duration.inMicroseconds * fraction).round());
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final barHeight = widget.height ?? (theme.progressThumbShape.isNone ? 22 : theme.thumbRadius * 2 + 10);

    Widget track = SizedBox(
      height: barHeight,
      child: ValueListenableBuilder<PlayerTransportState>(
        valueListenable: widget.controller.playbackListenable,
        builder: (context, playback, _) {
          return CustomPaint(
            painter: _ProgressPainter(
              theme: theme,
              trackHeight: _trackHeight,
              thumbRadius: widget.thumbRadius ?? theme.thumbRadius,
              thumb: theme.progressThumbShape,
              revealThumb: _growing,
              playbackFraction: playback.hasDuration ? playback.progress.clamp(0.0, 1.0) : 0,
              dragFraction: _dragFraction,
              bufferedFractions: _bufferedFractions(playback),
            ),
          );
        },
      ),
    );

    if (theme.progressTrackShape == PlayerProgressTrack.inset) {
      // Soft UI presses the track into the surface instead of laying a bar on
      // top of it, so the groove is the surface and only the played part is
      // painted.
      track = SoftSurface(
        theme: theme,
        inset: true,
        radius: (theme.trackHeight + 4) / 2,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: track,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          // A tap is a complete gesture: seeking right away is what the viewer
          // asked for.
          unawaited(widget.controller.seekTo(_positionFor(_fractionFor(details.localPosition, _barWidth))));
        },
        onHorizontalDragStart: (details) {
          final fraction = _fractionFor(details.localPosition, _barWidth);

          setState(() => _dragFraction = fraction);

          widget.onPreview?.call(_positionFor(fraction));
        },
        onHorizontalDragUpdate: (details) {
          final fraction = _fractionFor(details.localPosition, _barWidth);

          setState(() => _dragFraction = fraction);

          widget.onPreview?.call(_positionFor(fraction));
        },
        onHorizontalDragEnd: (_) => _commitDrag(),
        onHorizontalDragCancel: _commitDrag,
        child: Padding(padding: widget.padding, child: track),
      ),
    );
  }

  /// Width of the bar's own box, used to turn a local x into a fraction.
  double get _barWidth {
    final box = context.findRenderObject();

    if (box is RenderBox && box.hasSize) {
      return box.size.width;
    }

    return 0;
  }

  void _commitDrag() {
    final fraction = _dragFraction;

    if (fraction == null) {
      return;
    }

    setState(() => _dragFraction = null);

    widget.onPreview?.call(null);

    // One seek for the whole gesture, at the position the viewer let go of.
    unawaited(widget.controller.seekTo(_positionFor(fraction)));
  }
}

final class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({
    required this.theme,
    required this.trackHeight,
    required this.thumbRadius,
    required this.thumb,
    required this.revealThumb,
    required this.playbackFraction,
    required this.dragFraction,
    this.bufferedFractions = const <_Fraction>[],
  });

  final PlayerControlsTheme theme;
  final double trackHeight;
  final double thumbRadius;
  final PlayerProgressThumb thumb;
  final bool revealThumb;
  final double playbackFraction;
  final double? dragFraction;
  final List<_Fraction> bufferedFractions;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final track = Rect.fromLTWH(0, centerY - trackHeight / 2, size.width, trackHeight);
    final radius = Radius.circular(trackHeight / 2);

    // Soft UI has already sunk the groove into the surface; painting another
    // track on top of it would double the channel.
    if (theme.progressTrackShape != PlayerProgressTrack.inset) {
      canvas.drawRRect(RRect.fromRectAndRadius(track, radius), Paint()..color = theme.progressTrack);
    }

    // The buffered fill goes down before the played check and before the
    // thumb, because it answers "how far can I scrub without waiting" —
    // a fact that is most visible at the very start of a freshly opened
    // video, when played is zero and this early return used to swallow it.
    for (final buffered in bufferedFractions) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * buffered.start, track.top, size.width * buffered.extent, trackHeight),
          radius,
        ),
        Paint()..color = theme.progressBuffered,
      );
    }

    final played = dragFraction ?? playbackFraction;

    if (played <= 0) {
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, track.top, size.width * played, trackHeight), radius),
      Paint()..color = theme.progressPlayed,
    );

    if (thumb.isNone) {
      return;
    }

    // Fluent's dot is small at rest and grows under the pointer; a full circle
    // is always full size.
    final scale = thumb.isDot ? (revealThumb ? 1.0 : 0.55) : 1.0;

    canvas.drawCircle(Offset(size.width * played, centerY), thumbRadius * scale, Paint()..color = theme.progressThumb);
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) {
    return oldDelegate.trackHeight != trackHeight ||
        oldDelegate.thumbRadius != thumbRadius ||
        oldDelegate.thumb != thumb ||
        oldDelegate.revealThumb != revealThumb ||
        oldDelegate.playbackFraction != playbackFraction ||
        oldDelegate.dragFraction != dragFraction ||
        !_sameBuffered(oldDelegate.bufferedFractions, bufferedFractions) ||
        oldDelegate.theme != theme;
  }

  static bool _sameBuffered(List<_Fraction> a, List<_Fraction> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A start/end pair on the 0..1 track, used for the buffered fill.
@immutable
final class _Fraction {
  const _Fraction(this.start, this.end);

  final double start;
  final double end;

  double get extent => end - start;

  bool get isEmpty => extent <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _Fraction && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Progress bar plus the two time labels, laid out the way a bar wants.
///
/// The labels move during a drag because they read the same preview the bar
/// reports: a viewer dragging on a phone cannot see the thumb under their
/// finger, so the text is the feedback.
final class PlayerTimeline extends StatefulWidget {
  /// Creates a timeline row.
  const PlayerTimeline({
    required this.controller,
    required this.theme,
    super.key,
    this.showRemaining = false,
    this.padding,
    this.barHeight,
    this.hoverable,
    this.spacing,
  });

  /// Controller whose player this timeline drives.
  final PlayerControlsController controller;

  /// Colors and metrics.
  final PlayerControlsTheme theme;

  /// Whether the right label counts down instead of showing the duration.
  ///
  /// The Cupertino convention; the others show the total.
  final bool showRemaining;

  /// Padding around the row.
  final EdgeInsets? padding;

  /// Height of the bar's hit area.
  final double? barHeight;

  /// Whether the bar thickens under the pointer.
  final bool? hoverable;

  /// Gap between a label and the bar.
  final double? spacing;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

final class _PlayerTimelineState extends State<PlayerTimeline> {
  Duration? _preview;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final spacing = widget.spacing ?? theme.barGap;

    return ValueListenableBuilder<PlayerTransportState>(
      valueListenable: widget.controller.playbackListenable,
      builder: (context, playback, _) {
        final duration = playback.duration;
        final position = _preview ?? playback.position;
        final hours = duration.inHours > 0;

        final left = formatPlayerDuration(position, showHours: hours);

        final right = widget.showRemaining
            ? '-${formatPlayerDuration(duration - position, showHours: hours)}'
            : formatPlayerDuration(duration, showHours: hours);

        return Padding(
          padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              Text(left, style: theme.timeTextStyle, maxLines: 1, softWrap: false),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing),
                  child: PlayerProgressBar(
                    controller: widget.controller,
                    theme: theme,
                    height: widget.barHeight,
                    hoverable: widget.hoverable,
                    onPreview: (value) => setState(() => _preview = value),
                  ),
                ),
              ),
              Text(right, style: theme.timeTextStyle, maxLines: 1, softWrap: false),
            ],
          ),
        );
      },
    );
  }
}

/// Formats a duration the way player UIs do.
String formatPlayerDuration(Duration duration, {bool showHours = false}) {
  final value = duration.isNegative ? Duration.zero : duration;

  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);

  String two(int number) => number.toString().padLeft(2, '0');

  if (showHours || hours > 0) {
    return '$hours:${two(minutes)}:${two(seconds)}';
  }

  return '${two(minutes)}:${two(seconds)}';
}

/// Whether a thumb shape draws nothing at all.
extension PlayerProgressThumbShape on PlayerProgressThumb {
  /// Whether the played part ends in a rounded cap instead of a thumb.
  bool get isNone => this == PlayerProgressThumb.none;

  /// Whether the thumb is a dot that grows under the pointer.
  bool get isDot => this == PlayerProgressThumb.dot;
}
