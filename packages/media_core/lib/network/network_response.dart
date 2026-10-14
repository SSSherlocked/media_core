import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/network/network_manager.dart' show NetworkManager;

part 'network_response.freezed.dart';

/// Represents a network response.
///
/// A [NetworkResponse] contains the result returned
/// from a network operation.
///
/// Responsibilities:
///
/// - store response status
/// - store response data
/// - store response headers
/// - describe request outcome
///
/// It does not:
///
/// - perform network operations
/// - decode business models
/// - handle retries
///
/// Those belong to:
///
/// - [NetworkManager]
/// - higher-level operation layer
@freezed
abstract class NetworkResponse with _$NetworkResponse {
  /// Creates a successful network response.
  const factory NetworkResponse({
    /// HTTP-like status code.
    ///
    /// May be unavailable for custom transports.
    int? statusCode,

    /// Response body.
    Object? data,

    /// Response headers.
    Map<String, String>? headers,

    /// Request duration.
    Duration? duration,

    /// Whether response came from cache.
    @Default(false) bool fromCache,

    /// Request timestamp.
    DateTime? timestamp,
  }) = _NetworkResponse;

  /// Creates an empty response.
  factory NetworkResponse.empty() {
    return const NetworkResponse();
  }
}

/// Extension helpers for [NetworkResponse].
extension NetworkResponseExtension on NetworkResponse {
  /// Whether response has a successful status code.
  bool get isSuccess {
    if (statusCode == null) {
      return false;
    }

    return statusCode! >= 200 && statusCode! < 300;
  }

  /// Whether response contains data.
  bool get hasData {
    return data != null;
  }

  /// Whether response has headers.
  bool get hasHeaders {
    return headers != null && headers!.isNotEmpty;
  }
}
