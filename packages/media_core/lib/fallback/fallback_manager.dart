import 'package:media_core/fallback/fallback_context.dart';
import 'package:media_core/fallback/fallback_reason.dart';
import 'package:media_core/fallback/fallback_result.dart';
import 'package:media_core/fallback/library.dart' show BackendFallback, LineFallback, QualityFallback;

/// Coordinates a generic fallback lifecycle.
///
/// [FallbackManager] owns the active fallback context and provides a common
/// result factory for fallback operations.
///
/// It does not:
///
/// - select backend, line, or quality candidates
/// - resolve media sources
/// - execute a fallback operation
/// - control playback
///
/// Concrete fallback selection is delegated to:
///
/// - [BackendFallback]
/// - [LineFallback]
/// - [QualityFallback]
final class FallbackManager {
  /// Creates an idle manager with no active fallback context.
  FallbackManager();

  FallbackContext? _context;

  bool _disposed = false;

  /// The active fallback context, or `null` when no fallback is running.
  FallbackContext? get context => _context;

  /// Whether a fallback lifecycle is currently active.
  bool get isActive => _context != null;

  /// Starts a fallback lifecycle.
  void start(FallbackContext context) {
    _ensureNotDisposed();

    _context = context;
  }

  /// Creates a successful fallback result.
  FallbackResult success({required FallbackReason reason, required String target}) {
    _ensureNotDisposed();

    return FallbackResult.success(reason: reason, target: target);
  }

  /// Creates a failed fallback result.
  FallbackResult failure({required FallbackReason reason, String? message}) {
    _ensureNotDisposed();

    return FallbackResult.failure(reason: reason, message: message);
  }

  /// Completes the active fallback lifecycle.
  void complete() {
    _ensureNotDisposed();

    _context = null;
  }

  /// Cancels the active fallback lifecycle.
  void cancel() {
    _ensureNotDisposed();

    _context = null;
  }

  /// Replaces the current fallback context.
  void updateContext(FallbackContext context) {
    _ensureNotDisposed();

    _context = context;
  }

  /// Releases manager resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _context = null;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FallbackManager has been disposed.');
    }
  }
}
