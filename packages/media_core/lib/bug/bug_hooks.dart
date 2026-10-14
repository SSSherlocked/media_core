import 'dart:async';
import 'package:media_core/bug/fault_config.dart';
import 'package:media_core/bug/fault_event.dart' show FaultEvent;

/// Defines a module-level hook that can handle a fault injection.
///
/// A hook decides whether it supports a fault configuration and performs
/// the actual fault behavior when invoked.
///
/// Hooks do not create [FaultEvent] instances. The fault injector owns
/// event creation and lifecycle bookkeeping.
abstract interface class BugHook {
  /// Unique hook name.
  String get name;

  /// Returns whether this hook can handle [config].
  bool supports(FaultConfig config);

  /// Executes the fault behavior.
  FutureOr<void> onFault(FaultConfig config, {String? target, Object? metadata});
}

/// Registry of fault injection hooks.
final class BugHooks {
  /// Creates a registry pre-filled with [hooks], keyed by hook name.
  BugHooks({Iterable<BugHook> hooks = const <BugHook>[]}) {
    hooks.forEach(register);
  }

  final Map<String, BugHook> _hooks = <String, BugHook>{};

  bool _disposed = false;

  /// Whether this registry has been disposed.
  bool get isDisposed => _disposed;

  /// Number of registered hooks.
  int get length => _hooks.length;

  /// Whether no hooks are registered.
  bool get isEmpty => _hooks.isEmpty;

  /// Whether at least one hook is registered.
  bool get isNotEmpty => _hooks.isNotEmpty;

  /// Returns all registered hooks.
  Iterable<BugHook> get values => List<BugHook>.unmodifiable(_hooks.values);

  /// Returns all registered hook names.
  Iterable<String> get names => List<String>.unmodifiable(_hooks.keys);

  /// Registers a hook.
  ///
  /// Throws if another hook with the same name already exists.
  void register(BugHook hook) {
    _ensureNotDisposed();

    final name = _normalizeName(hook.name);

    if (name.isEmpty) {
      throw ArgumentError.value(hook.name, 'hook', 'Hook name must not be empty.');
    }

    if (_hooks.containsKey(name)) {
      throw StateError('A bug hook named "$name" is already registered.');
    }

    _hooks[name] = hook;
  }

  /// Registers a hook, replacing an existing hook with the same name.
  BugHook? registerOrReplace(BugHook hook) {
    _ensureNotDisposed();

    final name = _normalizeName(hook.name);

    if (name.isEmpty) {
      throw ArgumentError.value(hook.name, 'hook', 'Hook name must not be empty.');
    }

    return _hooks[name] = hook;
  }

  /// Unregisters a hook by name.
  BugHook? unregister(String name) {
    _ensureNotDisposed();

    final normalizedName = _normalizeName(name);

    if (normalizedName.isEmpty) {
      return null;
    }

    return _hooks.remove(normalizedName);
  }

  /// Finds a hook by name.
  BugHook? find(String name) {
    final normalizedName = _normalizeName(name);

    if (normalizedName.isEmpty) {
      return null;
    }

    return _hooks[normalizedName];
  }

  /// Finds the first hook supporting [config].
  BugHook? findSupporting(FaultConfig config) {
    for (final hook in _hooks.values) {
      if (hook.supports(config)) {
        return hook;
      }
    }

    return null;
  }

  /// Finds all hooks supporting [config].
  List<BugHook> findAllSupporting(FaultConfig config) {
    final result = <BugHook>[];

    for (final hook in _hooks.values) {
      if (hook.supports(config)) {
        result.add(hook);
      }
    }

    return List<BugHook>.unmodifiable(result);
  }

  /// Whether at least one hook supports [config].
  bool canInject(FaultConfig config) {
    return findSupporting(config) != null;
  }

  /// Executes the first supporting hook.
  ///
  /// Returns `true` when a hook was found and executed.
  /// Returns `false` when no hook supports [config].
  Future<bool> inject(FaultConfig config, {String? target, Object? metadata}) async {
    _ensureNotDisposed();

    final hook = findSupporting(config);

    if (hook == null) {
      return false;
    }

    await hook.onFault(config, target: target, metadata: metadata);

    return true;
  }

  /// Executes the first supporting hook and returns the hook instance.
  ///
  /// Returns `null` when no hook supports [config].
  Future<BugHook?> injectFirst(FaultConfig config, {String? target, Object? metadata}) async {
    _ensureNotDisposed();

    final hook = findSupporting(config);

    if (hook == null) {
      return null;
    }

    await hook.onFault(config, target: target, metadata: metadata);

    return hook;
  }

  /// Executes the first supporting hook and suppresses hook failures.
  ///
  /// Returns `true` only when a supporting hook completed successfully.
  Future<bool> tryInject(FaultConfig config, {String? target, Object? metadata}) async {
    try {
      return await inject(config, target: target, metadata: metadata);
    } on Object catch (_) {
      return false;
    }
  }

  /// Checks whether a named hook supports [config].
  bool supports(String name, FaultConfig config) {
    final hook = find(name);

    if (hook == null) {
      return false;
    }

    return hook.supports(config);
  }

  /// Removes all registered hooks.
  void clear() {
    _ensureNotDisposed();
    _hooks.clear();
  }

  /// Disposes the registry.
  ///
  /// Registered hooks are not disposed because [BugHook] does not own
  /// a lifecycle contract.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _hooks.clear();
  }

  String _normalizeName(String value) {
    return value.trim();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BugHooks has already been disposed.');
    }
  }
}
