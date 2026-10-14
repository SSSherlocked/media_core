import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/lifecycle/lifecycle_event.dart';
import 'package:media_core/lifecycle/lifecycle_observer.dart';
import 'package:media_core/lifecycle/lifecycle_snapshot.dart';
import 'package:media_core/lifecycle/lifecycle_state.dart';
import 'package:media_core/lifecycle/player_lifecycle.dart';
import 'package:rxdart/rxdart.dart';

/// Controls player lifecycle.
final class LifecycleController implements PlayerLifecycle {
  /// Creates a controller seeded in the initial (not-yet-created) lifecycle state.
  LifecycleController();

  LifecycleState _state = const LifecycleState();

  final BehaviorSubject<LifecycleSnapshot> _snapshotSubject = BehaviorSubject.seeded(LifecycleSnapshot.initial());

  final PublishSubject<LifecycleEvent> _eventSubject = PublishSubject();

  final List<LifecycleObserver> _observers = [];

  @override
  LifecycleSnapshot get snapshot {
    return _snapshotSubject.value;
  }

  @override
  Stream<LifecycleEvent> get events {
    return _eventSubject.stream;
  }

  /// Continuous stream of lifecycle snapshots, newest last.
  ///
  /// Unlike [snapshot], which reports only the latest value on demand, this
  /// emits every transition; subscribers that must react to state changes
  /// rather than poll for them listen here.
  Stream<LifecycleSnapshot> get snapshots {
    return _snapshotSubject.stream;
  }

  /// Registers [observer] to receive future lifecycle events.
  void addObserver(LifecycleObserver observer) {
    _observers.add(observer);
  }

  /// Unregisters [observer]; safe to call for an observer that was never added.
  void removeObserver(LifecycleObserver observer) {
    _observers.remove(observer);
  }

  @override
  void create() {
    _update(_state.markCreated(), LifecycleEventType.created);
  }

  @override
  void initialize() {
    _update(_state.markInitialized(), LifecycleEventType.initialized);
  }

  @override
  void activate() {
    _update(_state.markActive(), LifecycleEventType.activated);
  }

  @override
  void pause() {
    _update(_state.markPaused(), LifecycleEventType.paused);
  }

  @override
  void resume() {
    _update(_state.markActive(), LifecycleEventType.resumed);
  }

  @override
  void deactivate() {
    _update(_state.markInactive(), LifecycleEventType.inactive);
  }

  @override
  void detach() {
    _update(_state.markDetached(), LifecycleEventType.detached);
  }

  @override
  void dispose() {
    if (_state.disposed) {
      return;
    }

    _update(_state.markDisposing(), LifecycleEventType.disposing);

    _update(_state.markDisposed(), LifecycleEventType.disposed);

    // Observers outlive the streams: a subscriber that never removed itself
    // must not keep receiving (or be resurrected into) events after disposal.
    _observers.clear();

    unawaited(_snapshotSubject.close());
    unawaited(_eventSubject.close());
  }

  void _update(LifecycleState state, LifecycleEventType type) {
    // Lifecycle is one-way: once disposed, no transition may revive it. The
    // streams are closed at that point, so publishing would also throw.
    if (_state.disposed) {
      return;
    }

    _state = state;

    final event = LifecycleEvent.now(type);

    final snapshot = LifecycleSnapshot(state: state, updatedAt: clock.now());

    _snapshotSubject.add(snapshot);

    _eventSubject.add(event);

    for (final observer in List.of(_observers)) {
      observer.onLifecycleEvent(event);
    }
  }
}
