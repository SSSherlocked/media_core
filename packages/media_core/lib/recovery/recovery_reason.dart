import 'package:equatable/equatable.dart';

/// Describes why a recovery operation was requested.
///
/// A recovery reason is diagnostic and policy input data.
/// It does not decide which recovery action should be executed.
sealed class RecoveryReason extends Equatable {
  /// Records why recovery was requested, without deciding what to do about it.
  const RecoveryReason();

  const factory RecoveryReason.unknown() = RecoveryReasonUnknown;

  const factory RecoveryReason.network() = RecoveryReasonNetwork;

  const factory RecoveryReason.timeout() = RecoveryReasonTimeout;

  const factory RecoveryReason.decoder() = RecoveryReasonDecoder;

  const factory RecoveryReason.renderer() = RecoveryReasonRenderer;

  const factory RecoveryReason.source() = RecoveryReasonSource;

  const factory RecoveryReason.initialization() = RecoveryReasonInitialization;

  const factory RecoveryReason.interrupted() = RecoveryReasonInterrupted;

  const factory RecoveryReason.resource() = RecoveryReasonResource;

  /// Whether no backend evidence identified the trigger.
  bool get isUnknown => this is RecoveryReasonUnknown;

  /// Whether the trigger was reaching the media over the network.
  bool get isNetwork => this is RecoveryReasonNetwork;

  /// Whether the trigger was an operation exceeding its deadline.
  bool get isTimeout => this is RecoveryReasonTimeout;

  /// Whether the trigger was in the decode or demux path.
  bool get isDecoder => this is RecoveryReasonDecoder;

  /// Whether the trigger was in the render path.
  bool get isRenderer => this is RecoveryReasonRenderer;

  /// Whether the trigger was the media source itself.
  bool get isSource => this is RecoveryReasonSource;

  /// Whether the trigger was setup rather than steady-state playback.
  bool get isInitialization => this is RecoveryReasonInitialization;

  /// Whether playback was cut short by an interrupt or a replacement.
  bool get isInterrupted => this is RecoveryReasonInterrupted;

  /// Whether the trigger was memory, bandwidth, or another limited resource.
  bool get isResource => this is RecoveryReasonResource;

  /// Infers a reason from a raw backend message and an optional error.
  ///
  /// Adapters report free-form text: a media_kit error and an ijk error
  /// describe the same network outage in different words. Recovery has
  /// to act on both, so classification happens once, here, instead of
  /// in every caller that wants to know what went wrong.
  ///
  /// [error] is consulted as well, because a platform exception type
  /// name is often the only structured evidence available.
  static RecoveryReason classify(String message, [Object? error]) {
    final text = message.toLowerCase();
    final errorText = error?.runtimeType.toString().toLowerCase() ?? '';

    if (_matches(text, errorText, _networkHints)) {
      return const RecoveryReasonNetwork();
    }

    if (_matches(text, errorText, _timeoutHints)) {
      return const RecoveryReasonTimeout();
    }

    if (_matches(text, errorText, _decoderHints)) {
      return const RecoveryReasonDecoder();
    }

    if (_matches(text, errorText, _rendererHints)) {
      return const RecoveryReasonRenderer();
    }

    if (_matches(text, errorText, _sourceHints)) {
      return const RecoveryReasonSource();
    }

    if (_matches(text, errorText, _resourceHints)) {
      return const RecoveryReasonResource();
    }

    if (_matches(text, errorText, _initializationHints)) {
      return const RecoveryReasonInitialization();
    }

    if (_matches(text, errorText, _interruptedHints)) {
      return const RecoveryReasonInterrupted();
    }

    return const RecoveryReasonUnknown();
  }

  static bool _matches(String text, String errorText, List<String> hints) {
    for (final hint in hints) {
      if (text.contains(hint) || errorText.contains(hint)) {
        return true;
      }
    }

    return false;
  }

  // Note: no bare 'http' hint. Every failure message that quotes a URL
  // contains "http", so a bare hint classifies *everything* as a network
  // problem — including "unsupported source type" on an https:// stream.
  // Protocol failures are recognised through the words below instead.
  static const List<String> _networkHints = <String>[
    'network',
    'socket',
    'connection',
    'unreachable',
    'dns',
    'http error',
    'http status',
    'http 4',
    'http 5',
    'tls',
  ];

  static const List<String> _timeoutHints = <String>['timeout', 'timed out', 'deadline'];

  static const List<String> _decoderHints = <String>['decode', 'decoder', 'codec', 'demux'];

  static const List<String> _rendererHints = <String>['render', 'surface', 'texture', 'hwdec'];

  static const List<String> _sourceHints = <String>['source', 'format', '404', 'not found', 'invalid data'];

  static const List<String> _resourceHints = <String>['resource', 'memory', 'bandwidth', 'too many'];

  static const List<String> _initializationHints = <String>['init', 'initial', 'create', 'attach'];

  static const List<String> _interruptedHints = <String>['interrupt', 'abort', 'cancel', 'superseded'];

  @override
  List<Object?> get props => [];
}

/// Recovery reason could not be determined.
final class RecoveryReasonUnknown extends RecoveryReason {
  /// Creates the reason for a trigger that no backend evidence identifies.
  const RecoveryReasonUnknown();

  @override
  String toString() => 'RecoveryReasonUnknown';
}

/// Recovery was triggered by a network failure.
final class RecoveryReasonNetwork extends RecoveryReason {
  /// Creates the reason for a transport or connectivity failure while reaching the media.
  const RecoveryReasonNetwork();

  @override
  String toString() => 'RecoveryReasonNetwork';
}

/// Recovery was triggered by an operation timeout.
final class RecoveryReasonTimeout extends RecoveryReason {
  /// Creates the reason for an operation that exceeded its deadline.
  const RecoveryReasonTimeout();

  @override
  String toString() => 'RecoveryReasonTimeout';
}

/// Recovery was triggered by a decoder failure.
final class RecoveryReasonDecoder extends RecoveryReason {
  /// Creates the reason for a decode or demux failure in the media pipeline.
  const RecoveryReasonDecoder();

  @override
  String toString() => 'RecoveryReasonDecoder';
}

/// Recovery was triggered by a renderer failure.
final class RecoveryReasonRenderer extends RecoveryReason {
  /// Creates the reason for a failure in the render path.
  const RecoveryReasonRenderer();

  @override
  String toString() => 'RecoveryReasonRenderer';
}

/// Recovery was triggered by a source failure.
final class RecoveryReasonSource extends RecoveryReason {
  /// Creates the reason for a source that cannot be played as supplied.
  const RecoveryReasonSource();

  @override
  String toString() => 'RecoveryReasonSource';
}

/// Recovery was triggered by initialization failure.
final class RecoveryReasonInitialization extends RecoveryReason {
  /// Creates the reason for a failure while the pipeline was being set up.
  const RecoveryReasonInitialization();

  @override
  String toString() => 'RecoveryReasonInitialization';
}

/// Recovery was triggered because the operation was interrupted.
final class RecoveryReasonInterrupted extends RecoveryReason {
  /// Creates the reason for playback that was cut short or superseded.
  const RecoveryReasonInterrupted();

  @override
  String toString() => 'RecoveryReasonInterrupted';
}

/// Recovery was triggered by a resource failure.
final class RecoveryReasonResource extends RecoveryReason {
  /// Creates the reason for a memory, bandwidth, or other resource shortage.
  const RecoveryReasonResource();

  @override
  String toString() => 'RecoveryReasonResource';
}
