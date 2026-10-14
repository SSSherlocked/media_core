/// Utilities for parsing, formatting and manipulating HTTP headers.
abstract final class HeaderUtils {
  HeaderUtils._();

  /// Parses header lines into a map.
  ///
  /// Example:
  /// ```text
  /// Content-Type: application/json
  /// Authorization: Bearer xxx
  ///
  /// =>
  /// {
  ///   Content-Type: application/json,
  ///   Authorization: Bearer xxx
  /// }
  /// ```
  static Map<String, String> parse(Iterable<String>? headers) {
    if (headers == null) {
      return {};
    }

    final result = <String, String>{};

    for (final line in headers) {
      final index = line.indexOf(':');

      if (index <= 0) {
        continue;
      }

      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();

      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  /// Serializes headers into header lines.
  static List<String> serialize(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return [];
    }

    return headers.entries.map((entry) => '${entry.key}: ${entry.value}').toList();
  }

  /// Gets header value by name.
  static String? get(Map<String, String>? headers, String name) {
    if (headers == null) {
      return null;
    }

    final normalized = normalizeName(name);

    for (final entry in headers.entries) {
      if (normalizeName(entry.key) == normalized) {
        return entry.value;
      }
    }

    return null;
  }

  /// Checks whether header exists.
  static bool contains(Map<String, String>? headers, String name) {
    return get(headers, name) != null;
  }

  /// Adds or replaces a header.
  static Map<String, String> set(Map<String, String>? headers, String name, String value) {
    final result = <String, String>{};

    if (headers != null) {
      result.addAll(headers);
    }

    result.removeWhere((key, _) => normalizeName(key) == normalizeName(name));

    result[name] = value;

    return result;
  }

  /// Removes a header.
  static Map<String, String> remove(Map<String, String>? headers, String name) {
    final result = <String, String>{};

    if (headers == null) {
      return result;
    }

    result
      ..addAll(headers)
      ..removeWhere((key, _) => normalizeName(key) == normalizeName(name));

    return result;
  }

  /// Merges two header maps.
  ///
  /// Headers from [second] override [first].
  static Map<String, String> merge(Map<String, String>? first, Map<String, String>? second) {
    final result = <String, String>{};

    if (first != null) {
      result.addAll(first);
    }

    if (second != null) {
      result.addAll(second);
    }

    return result;
  }

  /// Converts headers into lower-case keys.
  static Map<String, String> normalize(Map<String, String>? headers) {
    if (headers == null) {
      return {};
    }

    final result = <String, String>{};

    for (final entry in headers.entries) {
      result[normalizeName(entry.key)] = entry.value;
    }

    return result;
  }

  /// Normalizes a header name.
  ///
  /// HTTP header names are case-insensitive.
  static String normalizeName(String name) {
    return name.trim().toLowerCase();
  }

  /// Returns content type.
  static String? contentType(Map<String, String>? headers) {
    return get(headers, 'content-type');
  }

  /// Returns content length.
  static int? contentLength(Map<String, String>? headers) {
    final value = get(headers, 'content-length');

    if (value == null) {
      return null;
    }

    return int.tryParse(value);
  }

  /// Returns user agent.
  static String? userAgent(Map<String, String>? headers) {
    return get(headers, 'user-agent');
  }

  /// Returns authorization header.
  static String? authorization(Map<String, String>? headers) {
    return get(headers, 'authorization');
  }

  /// Returns bearer token.
  static String? bearerToken(Map<String, String>? headers) {
    final value = authorization(headers);

    if (value == null) {
      return null;
    }

    const prefix = 'Bearer ';

    if (!value.startsWith(prefix)) {
      return null;
    }

    return value.substring(prefix.length).trim();
  }

  /// Creates authorization header.
  static Map<String, String> bearer(String token) {
    return {'Authorization': 'Bearer $token'};
  }

  /// Creates JSON content headers.
  static Map<String, String> json() {
    return {'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  /// Creates form content headers.
  static Map<String, String> formUrlEncoded() {
    return {'Content-Type': 'application/x-www-form-urlencoded'};
  }

  /// Returns whether response is JSON.
  static bool isJson(Map<String, String>? headers) {
    final type = contentType(headers);

    if (type == null) {
      return false;
    }

    return type.contains('application/json');
  }

  /// Returns whether response is text.
  static bool isText(Map<String, String>? headers) {
    final type = contentType(headers);

    if (type == null) {
      return false;
    }

    return type.startsWith('text/');
  }

  /// Returns whether response is compressed.
  static bool isCompressed(Map<String, String>? headers) {
    final encoding = get(headers, 'content-encoding');

    if (encoding == null) {
      return false;
    }

    return encoding.contains('gzip') || encoding.contains('br') || encoding.contains('deflate');
  }
}
