import 'dart:async';
import 'package:media_core/concurrency/library.dart' show AsyncLock;

/// A mutual exclusion lock.
///
/// A Mutex allows only one asynchronous operation to enter
/// the critical section at a time.
///
/// Difference from [AsyncLock]:
/// - Mutex exposes a more traditional lock/unlock API.
/// - Designed for protecting shared state.
///
/// Example:
/// ```dart
/// final mutex = Mutex();
///
/// await mutex.protect(() async {
///   counter++;
/// });
/// ```
class Mutex {
  Completer<void>? _owner;

  /// Number of acquirers currently waiting for the owner to release.
  ///
  /// A keyed container has to tell "free" apart from "handing the lock over to
  /// a waiter": [release] clears [_owner] before the waiter resumes, so
  /// [locked] alone would let the container drop a mutex that a queued
  /// operation is still holding.
  int _waiters = 0;

  /// Whether the mutex is currently locked.
  bool get locked => _owner != null;

  /// Whether the mutex is neither held nor awaited by anyone.
  bool get isIdle => _owner == null && _waiters == 0;

  /// Number of operations waiting for the lock.
  int get waiterCount => _waiters;

  /// Acquires the mutex.
  Future<void> acquire() async {
    while (_owner != null) {
      _waiters++;

      try {
        await _owner!.future;
      } finally {
        _waiters--;
      }
    }

    _owner = Completer<void>();
  }

  /// Releases the mutex.
  void release() {
    final owner = _owner;

    if (owner == null) {
      return;
    }

    _owner = null;

    if (!owner.isCompleted) {
      owner.complete();
    }
  }

  /// Executes [action] while holding the mutex.
  Future<T> protect<T>(Future<T> Function() action) async {
    await acquire();

    try {
      return await action();
    } finally {
      release();
    }
  }

  /// Executes a synchronous action while holding the mutex.
  T protectSync<T>(T Function() action) {
    if (locked) {
      throw StateError('Mutex is already locked');
    }

    _owner = Completer<void>();

    try {
      return action();
    } finally {
      release();
    }
  }
}

/// A mutex whose holder may acquire it again.
///
/// The lock is held until the outermost acquisition releases it.
///
/// Note:
/// Dart provides no asynchronous execution identity, so ownership cannot be
/// derived from the caller. Reentrancy is therefore granted through the
/// [protect] scope: the action runs in a zone carrying a live ownership marker
/// for this mutex, and only code running inside that scope is treated as the
/// owner. The marker is revoked when the outer call finishes, so a closure
/// that outlives the scope cannot keep re-entering the lock, and two unrelated
/// tasks that merely share a zone are never considered the same owner.
///
/// Manual [acquire]/[release] pairs are strictly exclusive and must not nest.
class ReentrantMutex {
  /// Zone key holding the live ownership marker of a [protect] scope.
  static final Object _ownershipKey = Object();

  final Object _identity = Object();

  Completer<void>? _owner;

  int _depth = 0;

  /// Whether the mutex is currently held by an operation.
  bool get locked => _owner != null;

  /// Number of nested acquisitions currently held.
  int get depth => _depth;

  /// Whether the current zone is inside a live [protect] scope of this mutex.
  bool get isOwnedByCurrentZone {
    final marker = Zone.current[_ownershipKey];

    return marker is _Ownership && marker.isLive && identical(marker.owner, _identity);
  }

  /// Acquires the mutex, re-entering when the current zone already owns it.
  Future<void> acquire() async {
    if (isOwnedByCurrentZone) {
      _depth++;
      return;
    }

    while (_owner != null) {
      await _owner!.future;
    }

    _owner = Completer<void>();
    _depth = 1;
  }

  /// Releases one nested acquisition; the lock is only freed at depth zero.
  void release() {
    final owner = _owner;

    if (owner == null) {
      return;
    }

    _depth--;

    if (_depth > 0) {
      return;
    }

    _owner = null;

    if (!owner.isCompleted) {
      owner.complete();
    }
  }

  /// Executes [action] while holding the mutex.
  ///
  /// A nested [protect] call made from inside [action] reuses the held lock
  /// instead of waiting for a release that cannot happen yet.
  Future<T> protect<T>(Future<T> Function() action) async {
    if (isOwnedByCurrentZone) {
      _depth++;

      try {
        return await action();
      } finally {
        release();
      }
    }

    await acquire();

    final ownership = _Ownership(_identity);

    try {
      return await runZoned(action, zoneValues: <Object, Object>{_ownershipKey: ownership});
    } finally {
      ownership.revoke();
      release();
    }
  }
}

/// Live ownership marker carried by a [ReentrantMutex.protect] zone.
final class _Ownership {
  _Ownership(this.owner);

  final Object owner;

  bool _live = true;

  bool get isLive => _live;

  void revoke() => _live = false;
}

/// Key based mutex.
///
/// Each key has an independent mutex.
///
/// Example:
/// ```dart
/// final mutex = KeyedMutex<String>();
///
/// await mutex.protect(
///   'epg',
///   () async {
///     await syncEpg();
///   },
/// );
/// ```
class KeyedMutex<K> {
  final Map<K, Mutex> _mutexes = {};

  /// Runs [action] while holding the mutex dedicated to [key].
  Future<T> protect<T>(K key, Future<T> Function() action) async {
    final mutex = _mutexes.putIfAbsent(key, Mutex.new);

    try {
      return await mutex.protect(action);
    } finally {
      // The entry may only be dropped by the last operation interested in it.
      // Removing it while a waiter is still queued would let the next caller
      // create a second mutex for the same key and run concurrently with it.
      if (identical(_mutexes[key], mutex) && mutex.isIdle) {
        _mutexes.remove(key);
      }
    }
  }

  /// Number of keys that currently have a mutex.
  int get length => _mutexes.length;

  /// Drops mutexes no operation is holding or waiting on.
  void cleanup() {
    _mutexes.removeWhere((_, mutex) => mutex.isIdle);
  }

  /// Drops every mutex, ignoring whether it is currently held.
  void clear() {
    _mutexes.clear();
  }
}
