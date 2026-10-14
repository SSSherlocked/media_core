import 'package:media_core/source/source_descriptor.dart';
import 'package:media_core/source/source_location.dart';
import 'package:media_core/source/source_request.dart';

/// Validates media sources.
///
/// [SourceValidator] checks whether a source request
/// or descriptor contains enough information for the
/// next processing stage.
///
/// Responsibilities:
///
/// - validate source input
/// - validate source descriptor
/// - provide validation errors
///
/// It does not:
///
/// - resolve sources
/// - inspect media streams
/// - open connections
///
/// Those belong to:
///
/// - SourceResolver
/// - SourceInspector
/// - Network layer
final class SourceValidator {
  /// Creates a source validator.
  const SourceValidator();

  /// Validates a source request.
  SourceValidationResult validateRequest(SourceRequest request) {
    final errors = <String>[];

    if (!request.resolvable) {
      errors.add('Source request does not contain uri or source id');
    }

    if (request.timeout != null && request.timeout!.isNegative) {
      errors.add('Timeout cannot be negative');
    }

    return SourceValidationResult(valid: errors.isEmpty, errors: errors);
  }

  /// Validates a source descriptor.
  SourceValidationResult validateDescriptor(SourceDescriptor descriptor) {
    final errors = <String>[];

    if (!descriptor.location.isValid) {
      errors.add('Source location is invalid');
    }

    if (descriptor.id.isUnknown) {
      errors.add('Source id is unknown');
    }

    if (descriptor.priority < 0) {
      errors.add('Source priority cannot be negative');
    }

    return SourceValidationResult(valid: errors.isEmpty, errors: errors);
  }

  /// Throws when request is invalid.
  void requireValidRequest(SourceRequest request) {
    final result = validateRequest(request);

    if (!result.valid) {
      throw SourceValidationException(result.errors);
    }
  }

  /// Throws when descriptor is invalid.
  void requireValidDescriptor(SourceDescriptor descriptor) {
    final result = validateDescriptor(descriptor);

    if (!result.valid) {
      throw SourceValidationException(result.errors);
    }
  }
}

/// Result of source validation.
final class SourceValidationResult {
  /// Creates validation result.
  const SourceValidationResult({required this.valid, required this.errors});

  /// Whether validation passed.
  final bool valid;

  /// Validation errors.
  final List<String> errors;

  /// Whether errors exist.
  bool get hasErrors {
    return errors.isNotEmpty;
  }
}

/// Exception thrown when source validation fails.
final class SourceValidationException implements Exception {
  /// Creates validation exception.
  SourceValidationException(this.errors);

  /// Validation errors.
  final List<String> errors;

  @override
  String toString() {
    return 'SourceValidationException($errors)';
  }
}
