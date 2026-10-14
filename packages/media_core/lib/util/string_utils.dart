/// String related utilities.
abstract final class StringUtils {
  StringUtils._();

  /// Returns empty string when value is null.
  static String emptyIfNull(String? value) {
    return value ?? '';
  }

  /// Checks whether string is empty.
  static bool isEmpty(String? value) {
    return value == null || value.isEmpty;
  }

  /// Checks whether string is blank.
  static bool isBlank(String? value) {
    return value == null || value.trim().isEmpty;
  }

  /// Checks whether string is not empty.
  static bool isNotEmpty(String? value) {
    return !isEmpty(value);
  }

  /// Checks whether string contains text.
  static bool contains(String? value, String query, {bool ignoreCase = false}) {
    if (value == null) {
      return false;
    }

    if (ignoreCase) {
      return value.toLowerCase().contains(query.toLowerCase());
    }

    return value.contains(query);
  }

  /// Returns trimmed string.
  static String trim(String? value) {
    return value?.trim() ?? '';
  }

  /// Capitalizes first character.
  static String capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value[0].toUpperCase() + value.substring(1);
  }

  /// Converts first character to lowercase.
  static String lowerFirst(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value[0].toLowerCase() + value.substring(1);
  }

  /// Converts string to snake_case.
  static String snakeCase(String value) {
    return value
        .replaceAllMapped(RegExp('([a-z])([A-Z])'), (match) {
          return '${match.group(1)}_${match.group(2)}';
        })
        .replaceAll(' ', '_')
        .toLowerCase();
  }

  /// Converts string to kebab-case.
  static String kebabCase(String value) {
    return snakeCase(value).replaceAll('_', '-');
  }

  /// Converts string to camelCase.
  static String camelCase(String value) {
    final parts = value.split(RegExp(r'[_\-\s]+')).where((e) => e.isNotEmpty).toList();

    if (parts.isEmpty) {
      return '';
    }

    return parts.first.toLowerCase() + parts.skip(1).map(capitalize).join();
  }

  /// Truncates string.
  static String truncate(String value, int maxLength, {String suffix = '...'}) {
    if (value.length <= maxLength) {
      return value;
    }

    if (maxLength <= suffix.length) {
      return value.substring(0, maxLength);
    }

    return value.substring(0, maxLength - suffix.length) + suffix;
  }

  /// Masks part of string.
  static String mask(String value, {int visibleStart = 2, int visibleEnd = 2, String maskChar = '*'}) {
    if (value.length <= visibleStart + visibleEnd) {
      return value;
    }

    final start = value.substring(0, visibleStart);

    final end = value.substring(value.length - visibleEnd);

    final maskedLength = value.length - visibleStart - visibleEnd;

    return start + maskChar * maskedLength + end;
  }

  /// Safely parses integer.
  static int? toInt(String? value) {
    return int.tryParse(value ?? '');
  }

  /// Safely parses double.
  static double? toDouble(String? value) {
    return double.tryParse(value ?? '');
  }

  /// Returns first non-empty value.
  static String firstNotEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (!isBlank(value)) {
        return value!;
      }
    }

    return '';
  }

  /// Joins non-empty values.
  static String joinNotEmpty(Iterable<String?> values, {String separator = ''}) {
    return values.where((e) => !isBlank(e)).join(separator);
  }

  /// Removes all whitespace.
  static String removeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), '');
  }

  /// Limits string bytes approximately.
  static String limitBytes(String value, int maxBytes) {
    if (value.length <= maxBytes) {
      return value;
    }

    return value.substring(0, maxBytes);
  }
}
