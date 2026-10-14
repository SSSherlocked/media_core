import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/network/network_manager.dart' show NetworkManager;
import 'package:media_core/source/source_headers.dart';

part 'network_request.freezed.dart';

/// Represents a network request.
///
/// A [NetworkRequest] describes a request that can be
/// executed by a network adapter.
///
/// Responsibilities:
///
/// - describe target URI
/// - describe HTTP method
/// - carry request headers
/// - define timeout/retry hints
///
/// It does not:
///
/// - open connections
/// - perform IO
/// - parse responses
///
/// Those belong to:
///
/// - [NetworkManager]
/// - platform network adapters
@freezed
abstract class NetworkRequest with _$NetworkRequest {
  /// Creates a network request.
  const factory NetworkRequest({
    /// Target resource URI.
    required Uri uri,

    /// HTTP method.
    @Default('GET') String method,

    /// Request headers.
    SourceHeaders? headers,

    /// Request body.
    ///
    /// The concrete type is controlled by
    /// the network implementation.
    Object? body,

    /// Connection timeout.
    Duration? connectTimeout,

    /// Response timeout.
    Duration? receiveTimeout,

    /// Maximum retry count.
    @Default(0) int maxRetries,

    /// Whether this request can use cache.
    @Default(false) bool cacheable,

    /// Extra request metadata.
    Map<String, Object?>? metadata,
  }) = _NetworkRequest;
}
