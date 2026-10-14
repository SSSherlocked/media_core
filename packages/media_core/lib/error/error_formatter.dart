import 'package:media_core/error/error_context.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_failure.dart';

/// Formats player errors into human-readable or diagnostic strings.
///
/// This class is responsible only for presentation of error information.
///
/// It does not:
/// - classify error codes;
/// - decide retry or fallback policy;
/// - modify [PlayerFailure];
/// - perform recovery;
/// - inspect backend state.
final class ErrorFormatter {
  /// Formatting rules are static, so instances exist only to satisfy
  /// dependency injection of a formatter.
  const ErrorFormatter();

  /// Formats a failure for normal user-facing messages.
  ///
  /// If the failure contains an explicit message, that message is returned.
  /// Otherwise, the error code is converted into a human-readable message.
  ///
  /// Machine-readable codes and diagnostic context are intentionally excluded.
  static String format(PlayerFailure failure) {
    final message = failure.message;

    if (message != null && message.trim().isNotEmpty) {
      return message.trim();
    }

    return formatCode(failure.code);
  }

  /// Formats only the human-readable name of an error code.
  static String formatCode(PlayerErrorCode code) {
    return _codeMessages[code.value] ?? _humanize(code.name);
  }

  /// Formats only the human-readable name of an error category.
  static String formatCategory(PlayerErrorCategory category) {
    return _categoryMessages[category.value] ?? _humanize(category.name);
  }

  /// Formats a failure for logs and diagnostics.
  ///
  /// Unlike [format], this method includes machine-readable information.
  /// Diagnostic context is included when available.
  static String formatLog(PlayerFailure failure) {
    final buffer = StringBuffer()
      ..write('PlayerIdentity failure')
      ..write(' [code=${failure.code.value}]');

    final category = failure.effectiveCategory;

    if (!category.isUnknown) {
      buffer.write(' [category=${category.value}]');
    }

    final message = failure.message;

    if (message != null && message.trim().isNotEmpty) {
      buffer
        ..write(': ')
        ..write(message.trim());
    }

    final context = failure.context;

    if (context != null && context.isNotEmpty) {
      buffer
        ..write(' [context=')
        ..write(formatContext(context))
        ..write(']');
    }

    final cause = failure.cause;

    if (cause != null) {
      buffer
        ..write(' [cause=')
        ..write(cause)
        ..write(']');
    }

    return buffer.toString();
  }

  /// Formats a failure for detailed debugging.
  ///
  /// This includes the stack trace when one is available.
  static String formatDebug(PlayerFailure failure) {
    final buffer = StringBuffer()
      ..writeln('PlayerFailure')
      ..writeln('  code: ${failure.code.value}');

    final category = failure.effectiveCategory;

    if (!category.isUnknown) {
      buffer.writeln('  category: ${category.value}');
    }

    final message = failure.message;

    if (message != null && message.trim().isNotEmpty) {
      buffer.writeln('  message: ${message.trim()}');
    }

    final context = failure.context;

    if (context != null && context.isNotEmpty) {
      buffer.writeln('  context: ${formatContext(context)}');
    }

    final cause = failure.cause;

    if (cause != null) {
      buffer.writeln('  cause: $cause');
    }

    final stackTrace = failure.stackTrace;

    if (stackTrace != null) {
      buffer
        ..writeln('  stackTrace:')
        ..writeln(stackTrace);
    }

    return buffer.toString().trimRight();
  }

  /// Formats diagnostic context into a compact representation.
  ///
  /// This method does not redact values or make policy decisions.
  ///
  /// Callers should avoid putting secrets, authentication tokens, cookies,
  /// authorization headers, or other sensitive information into
  /// [ErrorContext.metadata].
  static String formatContext(ErrorContext context) {
    final fields = <String, String>{};

    _put(fields, 'playerId', context.playerId?.value);
    _put(fields, 'sessionId', context.sessionId?.value);
    _put(fields, 'slotId', context.slotId?.value);
    _put(fields, 'sourceId', context.sourceId?.value);
    _put(fields, 'requestId', context.requestId?.value);
    _put(fields, 'operationId', context.operationId?.value);
    _put(fields, 'generationId', context.generationId?.value);

    _put(fields, 'operation', context.operation);
    _put(fields, 'lineId', context.lineId);
    _put(fields, 'quality', context.quality);
    _put(fields, 'uri', context.uri);
    _put(fields, 'platform', context.platform);
    _put(fields, 'backend', context.backend);
    _put(fields, 'adapter', context.adapter);
    _put(fields, 'state', context.state);

    final metadata = context.metadata;

    if (metadata.isNotEmpty) {
      fields['metadata'] = metadata.toString();
    }

    if (fields.isEmpty) {
      return '';
    }

    return fields.entries.map((entry) => '${entry.key}=${entry.value}').join(', ');
  }

  static void _put(Map<String, String> fields, String key, String? value) {
    if (value == null || value.trim().isEmpty) {
      return;
    }

    fields[key] = value;
  }

  static String _humanize(String value) {
    if (value.isEmpty) {
      return 'Unknown error';
    }

    final normalized = value.replaceAll('_', ' ').replaceAll('-', ' ').trim();

    if (normalized.isEmpty) {
      return 'Unknown error';
    }

    final words = normalized.split(RegExp(r'\s+'));

    return words
        .map((word) {
          if (word.isEmpty) {
            return word;
          }

          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  static const Map<String, String> _categoryMessages = <String, String>{
    'unknown': 'Unknown error',
    'invalidArgument': 'Invalid argument',
    'unsupported': 'Unsupported operation',
    'state': 'Invalid player state',
    'cancellation': 'Operation cancelled',
    'timeout': 'Operation timed out',
    'internal': 'Internal player error',

    'source': 'Media source error',
    'network': 'Network error',
    'http': 'HTTP error',
    'authentication': 'Authentication error',
    'security': 'Security error',

    'adapter': 'PlayerIdentity adapter error',
    'backend': 'Playback backend error',

    'decoder': 'Decoder error',
    'demuxer': 'Media demuxer error',
    'media': 'Media error',
    'playback': 'Playback error',

    'resource': 'Resource error',
    'memory': 'Memory pressure',
    'thermal': 'Thermal pressure',
    'bandwidth': 'Insufficient bandwidth',
    'concurrency': 'Concurrency error',

    'renderer': 'Renderer error',
    'geometry': 'Video geometry error',
    'presentation': 'Presentation error',

    'audio': 'Audio error',
    'recording': 'Recording error',
    'cache': 'Cache error',

    'lifecycle': 'PlayerIdentity lifecycle error',
    'recovery': 'Recovery error',
    'fallback': 'Fallback error',
  };

  static const Map<String, String> _codeMessages = <String, String>{
    'PLAYER_UNKNOWN': 'Unknown player error',
    'PLAYER_INVALID_ARGUMENT': 'Invalid argument',
    'PLAYER_INVALID_STATE': 'Invalid player state',
    'PLAYER_UNSUPPORTED': 'Operation is not supported',
    'PLAYER_CANCELLED': 'Operation cancelled',
    'PLAYER_TIMEOUT': 'Operation timed out',
    'PLAYER_STALE_GENERATION': 'Operation is no longer current',
    'PLAYER_SUPERSEDED': 'Operation was superseded',
    'PLAYER_INTERNAL': 'Internal player error',

    'SOURCE_MISSING': 'Media source is missing',
    'SOURCE_INVALID': 'Media source is invalid',
    'SOURCE_RESOLVE_FAILED': 'Unable to resolve media source',
    'SOURCE_INSPECT_FAILED': 'Unable to inspect media source',
    'SOURCE_VALIDATION_FAILED': 'Media source validation failed',
    'SOURCE_PROTOCOL_UNSUPPORTED': 'Media source protocol is not supported',
    'SOURCE_MEDIA_TYPE_UNSUPPORTED': 'Media source type is not supported',
    'SOURCE_FORMAT_UNSUPPORTED': 'Media source format is not supported',

    'NETWORK_ERROR': 'Network error',
    'NETWORK_UNAVAILABLE': 'Network is unavailable',
    'NETWORK_TIMEOUT': 'Network request timed out',
    'NETWORK_DNS_FAILED': 'DNS resolution failed',
    'NETWORK_CONNECTION_FAILED': 'Network connection failed',
    'NETWORK_CONNECTION_REFUSED': 'Network connection was refused',
    'NETWORK_ABORTED': 'Network request was aborted',

    'HTTP_ERROR': 'HTTP request failed',

    'AUTHENTICATION_REQUIRED': 'Authentication is required',
    'AUTHENTICATION_FAILED': 'Authentication failed',
    'AUTHORIZATION_FAILED': 'Authorization failed',
    'TLS_ERROR': 'Secure connection failed',

    'ADAPTER_UNAVAILABLE': 'PlayerIdentity adapter is unavailable',
    'ADAPTER_UNSUPPORTED': 'PlayerIdentity adapter is not supported',
    'ADAPTER_INITIALIZATION_FAILED': 'PlayerIdentity adapter initialization failed',
    'ADAPTER_DISPOSED': 'PlayerIdentity adapter has been disposed',

    'BACKEND_UNAVAILABLE': 'Playback backend is unavailable',
    'BACKEND_INITIALIZATION_FAILED': 'Playback backend initialization failed',
    'BACKEND_OPEN_FAILED': 'Playback backend failed to open the source',
    'BACKEND_PLAY_FAILED': 'Playback backend failed to start playback',
    'BACKEND_PAUSE_FAILED': 'Playback backend failed to pause',
    'BACKEND_STOP_FAILED': 'Playback backend failed to stop',
    'BACKEND_SEEK_FAILED': 'Playback backend failed to seek',
    'BACKEND_FATAL': 'Playback backend encountered a fatal error',

    'PLAYBACK_FAILED': 'Playback failed',
    'UNEXPECTED_STOP': 'Playback stopped unexpectedly',
    'PLAYBACK_INVALID_STATE': 'Playback is in an invalid state',
    'INVALID_SEEK_POSITION': 'Invalid seek position',
    'INVALID_PLAYBACK_RATE': 'Invalid playback rate',
    'INVALID_VOLUME': 'Invalid volume',

    'DECODER_ERROR': 'Media decoder error',
    'DECODER_UNAVAILABLE': 'Media decoder is unavailable',
    'CODEC_UNSUPPORTED': 'Media codec is not supported',
    'DEMUXER_ERROR': 'Media demuxer error',
    'MEDIA_CORRUPTED': 'Media data is corrupted',
    'MEDIA_METADATA_INVALID': 'Media metadata is invalid',
    'NO_PLAYABLE_STREAM': 'No playable stream was found',
    'STREAM_ENDED_UNEXPECTEDLY': 'Media stream ended unexpectedly',

    'RESOURCE_UNAVAILABLE': 'Required resource is unavailable',
    'RESOURCE_LIMIT_EXCEEDED': 'Resource limit was exceeded',
    'MEMORY_PRESSURE': 'System memory pressure detected',
    'THERMAL_PRESSURE': 'System thermal pressure detected',
    'INSUFFICIENT_BANDWIDTH': 'Network bandwidth is insufficient',

    'RENDERER_INITIALIZATION_FAILED': 'Renderer initialization failed',
    'RENDERER_SURFACE_FAILED': 'Renderer surface failed',
    'RENDERER_TEXTURE_FAILED': 'Renderer texture failed',
    'GEOMETRY_INVALID': 'Video geometry is invalid',
    'PRESENTATION_FAILED': 'Presentation failed',
    'PIP_FAILED': 'Picture-in-picture failed',
    'FULLSCREEN_FAILED': 'Fullscreen operation failed',
    'FLOATING_FAILED': 'Floating window operation failed',

    'AUDIO_INITIALIZATION_FAILED': 'Audio initialization failed',
    'AUDIO_FOCUS_FAILED': 'Audio focus operation failed',
    'AUDIO_ROUTE_FAILED': 'Audio route operation failed',
    'AUDIO_UNSUPPORTED': 'Audio is not supported',

    'RECORDING_UNSUPPORTED': 'Recording is not supported',
    'RECORDING_INITIALIZATION_FAILED': 'Recording initialization failed',
    'RECORDING_FAILED': 'Recording failed',
    'RECORDING_OUTPUT_INVALID': 'Recording output is invalid',
    'RECORDING_STORAGE_UNAVAILABLE': 'Recording storage is unavailable',

    'CACHE_ERROR': 'Cache error',
    'CACHE_STORAGE_UNAVAILABLE': 'Cache storage is unavailable',
    'CACHE_ENTRY_INVALID': 'Cache entry is invalid',
    'CACHE_LIMIT_EXCEEDED': 'Cache limit was exceeded',

    'CONCURRENCY_LIMIT_EXCEEDED': 'Concurrency limit was exceeded',
    'LOCK_UNAVAILABLE': 'Required lock is unavailable',

    'PLAYER_DISPOSED': 'PlayerIdentity has been disposed',
    'LIFECYCLE_INACTIVE': 'PlayerIdentity lifecycle is inactive',
    'LIFECYCLE_TRANSITION_FAILED': 'PlayerIdentity lifecycle transition failed',

    'FALLBACK_UNAVAILABLE': 'Fallback is unavailable',
    'FALLBACK_SELECTION_FAILED': 'Fallback selection failed',
    'RECOVERY_UNAVAILABLE': 'Recovery is unavailable',
    'RECOVERY_FAILED': 'Recovery failed',
    'RECOVERY_EXHAUSTED': 'Recovery attempts have been exhausted',
  };
}
