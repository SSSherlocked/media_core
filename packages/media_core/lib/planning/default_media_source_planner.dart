import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/planning/media_source_plan.dart';
import 'package:media_core/planning/media_source_planner.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// The default [MediaSourcePlanner].
///
/// Encodes the three rules media_core needs today:
///
/// 1. A progressive source is always directly playable — no backend
///    capability can turn a single stream into something it can't
///    consume.
/// 2. A composite source with a composite-capable backend is planned
///    as [CompositePlan]; the backend's own
///    [CompositeSupport.native] vs [CompositeSupport.externalAudio]
///    distinction is expressed by the same variant because the
///    planner is only deciding "does the adapter accept this
///    composite" — the how is the adapter's business.
/// 3. A composite source on a `CompositeSupport.none` backend is
///    planned as [UnsupportedPlan] rather than silently dropping to
///    the primary track. Nothing in the stack folds two essences into
///    one stream, so the only honest answers are "this backend takes
///    both inputs" or "no". Falling back without a plan is what lets a
///    provider "accidentally" ship Bilibili DASH audio to a Fijk build
///    with no sound — an explicit unsupported signal keeps that
///    failure at the layer that can react to it.
///
/// Responsibilities:
///
/// - map source + capabilities to a plan
///
/// It does not:
///
/// - merge or convert any essence
/// - open backends
/// - cache decisions across calls
///
/// Those belong to:
///
/// - PlayerAdapter
/// - PlayerKernel
///
/// Example:
///
/// ```dart
/// final planner = const DefaultMediaSourcePlanner();
/// final plan = planner.plan(compositeSource, mpvAdapter.capabilities);
/// if (plan case CompositePlan(:final source)) {
///   await adapter.openComposite(source);
/// }
/// ```
final class DefaultMediaSourcePlanner implements MediaSourcePlanner {
  /// Creates the default planner.
  const DefaultMediaSourcePlanner();

  @override
  MediaSourcePlan plan(MediaSource source, PlayerAdapterCapabilities capabilities) {
    final plan = _decide(source, capabilities);
    MediaCoreLog.debug(
      LogCategory.fallback,
      'media source plan: ${_planLabel(plan)} for ${source.type.name} source',
      fields: <String, Object?>{
        'sourceType': source.type.name,
        'plan': _planLabel(plan),
        'compositeSupport': capabilities.compositeSupport.name,
        if (source is CompositeMediaSource) 'video': source.videoTracks.length,
        if (source is CompositeMediaSource) 'audio': source.audioTracks.length,
        if (source is CompositeMediaSource) 'subtitle': source.subtitleTracks.length,
        if (plan is UnsupportedPlan) 'reason': plan.reason,
      },
    );
    return plan;
  }

  static String _planLabel(MediaSourcePlan plan) {
    return switch (plan) {
      DirectPlan() => 'direct',
      CompositePlan(:final mode) => 'composite/${mode.name}',
      UnsupportedPlan() => 'unsupported',
    };
  }

  MediaSourcePlan _decide(MediaSource source, PlayerAdapterCapabilities capabilities) {
    if (source is! CompositeMediaSource) {
      return DirectPlan(source);
    }

    if (capabilities.supportsComposite) {
      return CompositePlan(source, mode: capabilities.compositeSupport);
    }

    return UnsupportedPlan(
      'This backend takes one URL and cannot consume a composite source '
      '(${source.videoTracks.length} video + ${source.audioTracks.length} '
      'audio tracks). Register a backend whose composite support is native '
      'or external-audio, or hand it a single multiplexed URL.',
      source: source,
    );
  }
}
