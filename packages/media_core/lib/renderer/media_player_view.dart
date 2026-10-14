import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:media_core/adapter/player_video.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/screenshot/screenshot_surface.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/renderer/video_zoom_controller.dart';

/// Application-facing video widget for a [PlayerHandle].
///
/// This is the missing bridge between the kernel and the renderer
/// module: a consumer holds a [PlayerHandle], puts a [MediaPlayerView]
/// in the widget tree, and the view
///
/// - asks the attached adapter for its video widget through the
///   [PlayerVideo] interface (every video-capable adapter implements
///   it; adapters without video render the background only),
/// - re-builds when the recovery ladder swaps the backend, because it
///   follows [PlayerHandle.backendChanges] instead of holding on to the
///   previous adapter instance,
/// - hands the viewport fit to the adapter through the [PlayerVideo]
///   contract, so the surface is fitted by the same engine widget that
///   renders it,
/// - offers its video layer as a screenshot surface, so
///   [PlayerHandle.captureScreenshot] works on engines that have no
///   frame-capture API of their own,
/// - magnifies the video on request, through [zoom] and [enablePinchZoom].
///
/// The view never controls playback. Pausing, recovery and
/// lifecycle belong to the handle; this widget only renders.
///
/// ### Layout
///
/// The view does not impose a second layout system on the adapter's widget.
/// Earlier revisions wrapped the surface in an [AspectRatio] plus a
/// fitted [PlayerSurface], but an adapter's video widget already fits
/// itself (and a live stream arriving through the wrapped path could end
/// up composited black while audio played). The adapter's widget now
/// expands into the constraints the host gives this view — a host that
/// wants a letterboxed 16:9 box wraps this view in its own [AspectRatio].
///
/// ### Zooming
///
/// Magnification is a transform of the rendered surface, applied *inside*
/// the capture boundary:
///
/// ```text
/// RepaintBoundary   screenshots capture what the user sees
///  └ GestureDetector
///     └ ClipRect       crops what the magnification pushed outside
///        └ Transform   scale + translation
///           └ adapter video widget (fit, mirror, zoom)
/// ```
///
/// The order matters. The transform sits outside the adapter's own mirror
/// so a drag always moves the picture with the finger, and inside the clip
/// so magnifying crops the edges instead of painting over the host's UI.
final class MediaPlayerView extends StatefulWidget {
  const MediaPlayerView({
    required this.handle,
    super.key,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.mirror = false,
    this.backgroundColor = const Color(0xFF000000),
    this.captureBoundary = true,
    this.zoom,
    this.enablePinchZoom = false,
    this.enableDoubleTapZoom = false,
    this.resetZoomOnSourceChange = true,
  });

  /// The player whose video is rendered.
  final PlayerHandle handle;

  /// How the video is fitted into the view.
  ///
  /// Applied through the [PlayerVideo.setVideoFit] contract — the adapter's
  /// own surface widget performs the fitting. Re-applied when the value
  /// changes and when the recovery ladder swaps in another backend.
  final BoxFit fit;

  /// Alignment of the rendered content.
  final AlignmentGeometry alignment;

  /// Whether to mirror the rendered image horizontally.
  final bool mirror;

  /// Background color while no video widget is available.
  final Color? backgroundColor;

  /// Whether this view offers its video layer for screenshots.
  ///
  /// A [RepaintBoundary] around the video is what makes a surface capture
  /// possible, and it costs one extra composited layer. Disable it in a host
  /// that never takes screenshots and renders many players at once.
  final bool captureBoundary;

  /// Zoom applied to the video.
  ///
  /// Pass one to read the current magnification, to reset it, or to remember
  /// it across widgets — a feed that keeps each item's zoom, or a small window
  /// that opens with the zoom the inline view had. When omitted, the view owns
  /// one internally for as long as it needs it, which is enough for gestures
  /// alone.
  final VideoZoomController? zoom;

  /// Whether the view magnifies the video with a two-finger pinch.
  ///
  /// Off by default, and deliberately so: the gesture layer competes with the
  /// host's own gestures. A video inside a vertical feed or a horizontally
  /// paged gallery must either keep this off or stop its scrollable while
  /// `zoom.isZoomed` (`physics: NeverScrollableScrollPhysics`), because a
  /// magnified picture wants the drag for panning.
  ///
  /// Unlike an unzoomed single-finger drag — which a parent scrollable still
  /// wins — a pinch is claimed as soon as a second finger lands.
  final bool enablePinchZoom;

  /// Whether a double tap magnifies the video.
  ///
  /// Separate from [enablePinchZoom] because the two answer different
  /// questions: a feed wants no pinch (it swipes) but may still want double-tap
  /// to zoom, and a desktop player wants neither (a double click is
  /// fullscreen). A double tap toggles between 1x and
  /// [VideoZoomController.doubleTapScale], around the point that was tapped.
  final bool enableDoubleTapZoom;

  /// Whether opening another source returns the zoom to 1x.
  ///
  /// Default true: the next video is a different picture, and inheriting the
  /// previous magnification of a differently shaped video is disorienting.
  final bool resetZoomOnSourceChange;

  @override
  State<MediaPlayerView> createState() => _MediaPlayerViewState();
}

final class _MediaPlayerViewState extends State<MediaPlayerView> {
  @override
  void initState() {
    super.initState();

    _bind(widget.handle);
  }

  StreamSubscription<void>? _backendSubscription;
  StreamSubscription<void>? _geometrySubscription;
  StreamSubscription<PlayerSource?>? _sourceSubscription;

  /// Boundary wrapping the video layer, used as a screenshot surface.
  ///
  /// Wraps the video only: everything the host stacks on top of this view
  /// stays out of a capture, which is what a "save this frame" action should
  /// produce.
  final GlobalKey _captureKey = GlobalKey();

  /// Surface handed to the handle while this view is bound to it.
  late final ScreenshotSurface _surface = ScreenshotSurface(boundaryKey: _captureKey);

  /// The video output currently attached, so its surface lifecycle can be
  /// released when the widget goes away or the handle changes.
  PlayerVideo? _attached;

  /// The video output the current build wants.
  PlayerVideo? _desired;

  /// The engine's picture widget for the output currently rendered.
  ///
  /// Cached against the output's identity and the background behind it, because
  /// this widget is the most expensive one in the tree: building it constructs
  /// the engine's own surface widget (a texture or platform view) for no change
  /// at all. A host page that rebuilds on every transport tick — the natural way
  /// to drive chrome from playback state — would otherwise rebuild the surface
  /// tens of times a second. Reusing the identical instance lets Flutter skip
  /// the subtree entirely.
  Widget? _picture;
  PlayerVideo? _pictureOutput;
  Color? _pictureBackground;

  bool _surfaceSyncScheduled = false;

  /// Zoom state, owned by this view when the host did not supply one.
  late VideoZoomController _zoom = widget.zoom ?? VideoZoomController();

  /// Scale at the start of the running pinch, so the reported cumulative scale
  /// is applied as a ratio instead of being multiplied in every frame.
  double _gestureStartScale = 1.0;

  /// Where the last double tap landed, in view coordinates.
  Offset _doubleTapPosition = Offset.zero;

  /// Size of the video box, needed by every zoom operation for clamping.
  Size _viewSize = Size.zero;

  /// Whether the view should apply (and may change) a zoom transform.
  bool get _zoomEnabled => widget.enablePinchZoom || widget.enableDoubleTapZoom || widget.zoom != null;

  @override
  void didUpdateWidget(MediaPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.zoom, widget.zoom)) {
      // A host that swaps controllers owns the lifetime of what it passes
      // in; only the one this view created is its to dispose.
      _releaseOwnedZoom();

      _zoom = widget.zoom ?? VideoZoomController();
    }

    if (!identical(oldWidget.handle, widget.handle)) {
      _bind(widget.handle);

      return;
    }

    if (oldWidget.fit != widget.fit) {
      _applyFit(widget.handle);
    }

    // The capture boundary may have been switched off (or on) for the same
    // handle; the surface has to follow, or a capture would read a boundary
    // that is no longer in the tree.
    if (oldWidget.captureBoundary != widget.captureBoundary) {
      _syncSurfaceAttachment(widget.handle);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Refreshed on every dependency change so a window moved to another
    // display captures at that display's density.
    _surface.devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context);
  }

  @override
  void dispose() {
    _unbind();

    _releaseOwnedZoom();

    super.dispose();
  }

  /// The handle this view registered its screenshot surface with, if any.
  PlayerHandle? _surfaceHost;

  /// Follows [handle] for as long as this widget displays it.
  ///
  /// Both subscriptions are held and cancelled: without that, a widget whose
  /// handle changed kept listening to the previous player, and every rebuild
  /// added another pair that was never released.
  void _bind(PlayerHandle handle) {
    _unbind();

    _syncSurfaceAttachment(handle);

    _applyFit(handle);

    _backendSubscription = handle.backendChanges.listen((_) {
      if (mounted) {
        // The replacement adapter must not inherit the old engine's fit.
        _applyFit(handle);
        setState(() {});
      }
    });

    _geometrySubscription = handle.geometryController.state.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });

    // A new source is a different picture; the previous magnification belongs
    // to what is no longer on screen. The stream also reports the source being
    // closed, which is when the reset matters least but is still correct.
    _sourceSubscription = handle.sourceChanges.listen((_) {
      if (widget.resetZoomOnSourceChange) {
        _zoom.reset();
      }
    });
  }

  /// Keeps the handle's screenshot surface in sync with this widget.
  ///
  /// A surface is offered only while this widget renders the player *and* the
  /// capture boundary is enabled: attaching one whose boundary is not in the
  /// tree would make a capture report a surface it can never read.
  void _syncSurfaceAttachment(PlayerHandle handle) {
    if (_surfaceHost != null && !identical(_surfaceHost, handle)) {
      _releaseSurface();
    }

    if (!widget.captureBoundary || identical(_surfaceHost, handle)) {
      return;
    }

    _surfaceHost = handle;

    handle.attachScreenshotSurface(_surface);
  }

  /// Hands the viewport fit to the active adapter.
  ///
  /// Called from lifecycle callbacks and the backend-change stream — never
  /// during build — because notifying the adapter's fit listeners mid-frame
  /// would mark widgets dirty while the frame is being built.
  void _applyFit(PlayerHandle handle) {
    if (handle.adapter case final PlayerVideo video) {
      video.setVideoFit(widget.fit);
    }
  }

  void _releaseSurface() {
    _surfaceHost?.detachScreenshotSurface(_surface);

    _surfaceHost = null;
  }

  void _unbind() {
    _releaseSurface();

    _backendSubscription?.cancel();
    _backendSubscription = null;

    _geometrySubscription?.cancel();
    _geometrySubscription = null;

    _sourceSubscription?.cancel();
    _sourceSubscription = null;

    // `attach`/`detach` exist for surfaces with an explicit lifecycle
    // (SurfaceTexture / PlatformView based engines); they are no-ops for the
    // engines that own their texture, which is why calling them
    // unconditionally is safe.
    final attached = _attached;

    _attached = null;
    _desired = null;

    if (attached != null) {
      unawaited(attached.detach());
    }
  }

  /// Attaches/detaches the surface after the frame.
  ///
  /// The transition is decided in `build` but performed here: `attach` can hit
  /// a platform channel, and a build pass must not.
  void _scheduleSurfaceSync() {
    if (_surfaceSyncScheduled) {
      return;
    }

    _surfaceSyncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _surfaceSyncScheduled = false;

      if (!mounted) {
        return;
      }

      final desired = _desired;
      final previous = _attached;

      if (identical(desired, previous)) {
        return;
      }

      _attached = desired;

      if (previous != null) {
        unawaited(previous.detach());
      }

      if (desired != null) {
        unawaited(desired.attach());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final PlayerVideo? video = switch (handle.adapter) {
      final PlayerVideo output when output.available => output,
      _ => null,
    };

    _desired = video;

    if (!identical(video, _attached)) {
      _scheduleSurfaceSync();
    }

    // Without a video widget there is nothing to render: an audio-only
    // player, or one whose surface is not ready yet, paints its background.
    final Widget picture = _pictureFor(video);

    Widget content = picture;

    if (widget.mirror) {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: content,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _trackViewSize(constraints.biggest);

        // Outermost first: the capture boundary has to see the magnification
        // (a screenshot is "what I see"), and the gesture layer has to work
        // in view coordinates — inside the transform its focal points would
        // be content coordinates.
        return _withCaptureBoundary(_withGestures(_withZoom(content)));
      },
    );
  }

  /// Builds — or reuses — the picture for [video].
  ///
  /// The cache is keyed on the output's identity and on the background painted
  /// when there is none: both are the only inputs to the widget below, and the
  /// fit, the alignment and the mirror are applied outside it (the fit through
  /// the adapter's own notifier, the rest by the wrappers in [build]).
  Widget _pictureFor(PlayerVideo? video) {
    final background = _backgroundColor;

    if (identical(video, _pictureOutput) && _pictureBackground == background && _picture != null) {
      return _picture!;
    }

    _pictureOutput = video;
    _pictureBackground = background;

    return _picture = video == null
        ? ColoredBox(color: background, child: const SizedBox.expand())
        // Keyed per adapter instance: on a backend swap the old surface
        // unmounts instead of being updated onto a foreign controller.
        : KeyedSubtree(
            key: ValueKey('${video.runtimeType}_${identityHashCode(video)}'),
            child: video.build(),
          );
  }

  /// Wraps [child] in the capture boundary when the host wants screenshots.
  Widget _withCaptureBoundary(Widget child) {
    return widget.captureBoundary ? RepaintBoundary(key: _captureKey, child: child) : child;
  }

  /// Wraps [child] in the zoom transform when zooming is in play.
  ///
  /// The clip and the transform are rebuilt on their own, with [child] passed
  /// straight through, so a drag never re-builds the engine's video widget —
  /// the picture subtree is not touched while the user pinches. At rest there
  /// is no wrapper at all: a host that passes a controller to read the zoom
  /// pays nothing for a video nobody magnified.
  Widget _withZoom(Widget child) {
    if (!_zoomEnabled) {
      return child;
    }

    return ListenableBuilder(
      listenable: _zoom,
      child: child,
      builder: (context, child) {
        if (!_zoom.isActive) {
          return child!;
        }

        return ClipRect(child: Transform(transform: _zoom.matrix, child: child));
      },
    );
  }

  /// Wraps [child] in the gesture layer, when the host asked for gestures.
  ///
  /// Only the recognizers that were asked for are installed: a GestureDetector
  /// with a scale callback claims drags in the gesture arena, and a host that
  /// wanted nothing but a double tap must not pay for that.
  Widget _withGestures(Widget child) {
    final pinch = widget.enablePinchZoom;
    final doubleTap = widget.enableDoubleTapZoom;

    if (!pinch && !doubleTap) {
      return child;
    }

    return GestureDetector(
      onScaleStart: pinch ? (details) => _gestureStartScale = _zoom.scale : null,
      onScaleUpdate: pinch
          ? (details) {
              // A pinch reports the scale relative to the start of the gesture,
              // so it is applied as a ratio against the scale recorded then:
              // feeding `details.scale` in every frame would compound it.
              if (details.pointerCount > 1) {
                _zoom.scaleBy(_gestureStartScale * details.scale / _zoom.scale, details.localFocalPoint, _viewSize);

                return;
              }

              _zoom.panBy(details.focalPointDelta, _viewSize);
            }
          : null,
      onScaleEnd: pinch ? (_) => _zoom.settle(_viewSize) : null,
      onDoubleTapDown: doubleTap ? (details) => _doubleTapPosition = details.localPosition : null,
      onDoubleTap: doubleTap ? () => _zoom.toggleAt(_doubleTapPosition, _viewSize) : null,
      child: child,
    );
  }

  /// Records the size of the video box and re-clamps the zoom when it changes.
  ///
  /// Rotation, fullscreen and split-screen resize all move the bounds the
  /// translation was clamped against. The re-clamp is deferred to after the
  /// frame because it notifies listeners, and notifying during a build is an
  /// error.
  void _trackViewSize(Size size) {
    if (size == _viewSize || size.isEmpty) {
      return;
    }

    _viewSize = size;

    if (!_zoomEnabled || !_zoom.isActive) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _zoom.reclamp(_viewSize);
      }
    });
  }

  Color get _backgroundColor => widget.backgroundColor ?? const Color(0xFF000000);

  /// Drops the zoom controller this view created, if it created one.
  ///
  /// A controller handed in by the host is the host's to dispose: it may
  /// outlive this widget on purpose (a feed remembering an item's zoom).
  void _releaseOwnedZoom() {
    if (widget.zoom != null) {
      return;
    }

    _zoom.dispose();
  }
}
