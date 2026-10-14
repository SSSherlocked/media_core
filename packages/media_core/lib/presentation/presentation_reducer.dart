import 'package:media_core/presentation/presentation_event.dart';
import 'package:media_core/presentation/presentation_state.dart';

/// Reduces presentation events into presentation states.
///
/// PresentationReducer is a pure state transformer.
///
/// Responsibilities:
///
/// - convert events into states
/// - handle presentation lifecycle
/// - synchronize generation
/// - clear transition state
/// - handle errors
///
/// Does not:
///
/// - call platform APIs
/// - perform async operations
/// - dispatch requests
/// - manage lifecycle
///
/// Flow:
///
/// PresentationEvent
///        │
///        ▼
/// PresentationReducer
///        │
///        ▼
/// PresentationState
///
final class PresentationReducer {
  /// Creates the stateless reducer.
  const PresentationReducer();

  /// Applies an event and returns next state.
  PresentationState reduce(PresentationState state, PresentationEvent event) {
    //
    // Ignore stale async callbacks.
    //
    if (event.generation < state.generation) {
      return state;
    }

    final generation = event.generation > state.generation ? event.generation : state.generation;

    return switch (event) {
      //
      // Transition started.
      //
      final PresentationStarted event => state.copyWith(
        targetMode: event.mode,
        transitioning: true,
        generation: generation,
        error: null,
      ),

      //
      // Transition completed.
      //
      final PresentationCompleted event => state.copyWith(
        mode: event.mode,
        targetMode: null,
        transitioning: false,
        generation: generation,
        error: null,
      ),

      //
      // Transition failed.
      //
      final PresentationFailed event => state.copyWith(
        targetMode: null,
        transitioning: false,
        generation: generation,
        error: event.error,
      ),

      //
      // Platform changed state externally.
      //
      final PresentationChanged event => state.copyWith(
        mode: event.mode,
        targetMode: null,
        transitioning: false,
        generation: generation,
        error: null,
      ),

      //
      // Controller disposed.
      //
      PresentationDisposed _ => state.copyWith(targetMode: null, transitioning: false, generation: generation),
    };
  }
}
