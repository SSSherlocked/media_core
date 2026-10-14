import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/planning/media_source_plan.dart';
import 'package:media_core/source/media_source.dart';

/// Decides how a [MediaSource] should be handled by a specific
/// backend.
///
/// [MediaSourcePlanner] is the seam between "what the provider
/// produced" and "what the adapter will accept". It runs before any
/// engine call so the caller can log the decision or show a friendly
/// error without either the provider or the backend having to know the
/// other exists.
///
/// Planning is a pure, synchronous function of `(source,
/// capabilities)`. Anything asynchronous — probing, fetching, opening
/// a backend — is the caller's job after the plan is returned.
///
/// Responsibilities:
///
/// - map a source plus capabilities to a plan
///
/// It does not:
///
/// - open a backend
/// - fetch or merge media
///
/// Those belong to:
///
/// - PlayerAdapter
/// - PlayerKernel
abstract interface class MediaSourcePlanner {
  /// Produces the plan for [source] against [capabilities].
  MediaSourcePlan plan(MediaSource source, PlayerAdapterCapabilities capabilities);
}
