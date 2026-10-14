/// Validation utilities.
abstract final class ValidationUtils {
  ValidationUtils._();

  /// Checks whether value is null.
  static bool isNull(Object? value) {
    return value == null;
  }

  /// Checks whether value is not null.
  static bool isNotNull(Object? value) {
    return value != null;
  }

  /// Checks whether string is empty.
  static bool isEmpty(String? value) {
    return value == null || value.isEmpty;
  }

  /// Checks whether string is not empty.
  static bool isNotEmpty(String? value) {
    return value != null && value.isNotEmpty;
  }

  /// Checks whether string contains text.
  static bool hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  /// Validates required string.
  static String? required(String? value, {String message = 'Value is required'}) {
    if (!hasText(value)) {
      return message;
    }

    return null;
  }

  /// Validates minimum string length.
  static String? minLength(String? value, int length, {String? message}) {
    if (value == null) {
      return null;
    }

    if (value.length < length) {
      return message ?? 'Length must be at least $length';
    }

    return null;
  }

  /// Validates maximum string length.
  static String? maxLength(String? value, int length, {String? message}) {
    if (value == null) {
      return null;
    }

    if (value.length > length) {
      return message ?? 'Length must not exceed $length';
    }

    return null;
  }

  /// Validates integer range.
  static String? range(num? value, num min, num max, {String? message}) {
    if (value == null) {
      return null;
    }

    if (value < min || value > max) {
      return message ?? 'Value must be between $min and $max';
    }

    return null;
  }

  /// Validates positive number.
  static String? positive(num? value, {String? message}) {
    if (value == null) {
      return null;
    }

    if (value <= 0) {
      return message ?? 'Value must be positive';
    }

    return null;
  }

  /// Validates non-negative number.
  static String? nonNegative(num? value, {String? message}) {
    if (value == null) {
      return null;
    }

    if (value < 0) {
      return message ?? 'Value must not be negative';
    }

    return null;
  }

  /// Validates URL format.
  static String? url(String? value, {String? message}) {
    if (!hasText(value)) {
      return null;
    }

    final uri = Uri.tryParse(value!);

    if (uri == null || !uri.hasAbsolutePath && uri.host.isEmpty) {
      return message ?? 'Invalid URL';
    }

    return null;
  }

  /// Validates URI.
  static bool isUri(String? value) {
    if (!hasText(value)) {
      return false;
    }

    return Uri.tryParse(value!) != null;
  }

  /// Validates email format.
  static String? email(String? value, {String? message}) {
    if (!hasText(value)) {
      return null;
    }

    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!regex.hasMatch(value!)) {
      return message ?? 'Invalid email';
    }

    return null;
  }

  /// Validates enum value.
  static bool isEnum<T>(T value, Iterable<T> values) {
    return values.contains(value);
  }

  /// Validates list is not empty.
  static String? listNotEmpty<T>(List<T>? value, {String? message}) {
    if (value == null || value.isEmpty) {
      return message ?? 'List must not be empty';
    }

    return null;
  }

  /// Validates map is not empty.
  static String? mapNotEmpty<K, V>(Map<K, V>? value, {String? message}) {
    if (value == null || value.isEmpty) {
      return message ?? 'Map must not be empty';
    }

    return null;
  }

  /// Throws [ArgumentError] when condition fails.
  static void ensure({required bool condition, required String message}) {
    if (!condition) {
      throw ArgumentError(message);
    }
  }

  /// Requires non-null value.
  static T require<T>(T? value, {String message = 'Value must not be null'}) {
    if (value == null) {
      throw ArgumentError(message);
    }

    return value;
  }
}
