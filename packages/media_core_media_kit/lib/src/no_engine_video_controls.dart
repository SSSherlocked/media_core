import 'package:flutter/widgets.dart' show SizedBox, Widget;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// A [mkv.Video] control layer that draws nothing.
///
/// `media_core` renders its own control chrome, so the engine's must be
/// suppressed. The pinned fork declares its `NoVideoControls` as
/// `const NoVideoControls = null`, which reaches a `VideoControlsBuilder?`
/// parameter as `dynamic` — an implicit downcast the analyzer correctly refuses —
/// and is even *invoked* as a function inside the fork's own adaptive path
/// (`adaptive.dart` calls `NoVideoControls(state)`), which cannot work on a null
/// constant. A builder that returns nothing is what upstream's `NoVideoControls`
/// actually is, so that is what this package passes.
Widget noEngineVideoControls(mkv.VideoState state) => const SizedBox.shrink();
