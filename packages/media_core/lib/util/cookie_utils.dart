/// Utilities for parsing, formatting and manipulating HTTP cookies.
abstract final class CookieUtils {
  CookieUtils._();

  /// Parses a Cookie header string into a map.
  ///
  /// Example:
  /// `a=1; b=2` -> `{a: 1, b: 2}`
  static Map<String, String> parse(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      return {};
    }

    final result = <String, String>{};

    final parts = cookieHeader.split(';');

    for (final part in parts) {
      final index = part.indexOf('=');

      if (index <= 0) {
        continue;
      }

      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();

      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  /// Converts cookies into a Cookie header string.
  ///
  /// Example:
  /// `{a:1,b:2}` -> `a=1; b=2`
  static String serialize(Map<String, String>? cookies) {
    if (cookies == null || cookies.isEmpty) {
      return '';
    }

    return cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  /// Gets a cookie value by name.
  static String? get(String? cookieHeader, String name) {
    final cookies = parse(cookieHeader);

    return cookies[name];
  }

  /// Returns whether a cookie exists.
  static bool contains(String? cookieHeader, String name) {
    return parse(cookieHeader).containsKey(name);
  }

  /// Adds or replaces a cookie.
  static String set(String? cookieHeader, String name, String value) {
    final cookies = parse(cookieHeader);

    cookies[name] = value;

    return serialize(cookies);
  }

  /// Removes a cookie.
  static String remove(String? cookieHeader, String name) {
    final cookies = parse(cookieHeader)..remove(name);

    return serialize(cookies);
  }

  /// Merges two cookie strings.
  ///
  /// Cookies from [second] override cookies from [first].
  static String merge(String? first, String? second) {
    final result = <String, String>{}
      ..addAll(parse(first))
      ..addAll(parse(second));

    return serialize(result);
  }

  /// Converts cookies into HTTP request headers.
  static Map<String, String> toHeaders(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) {
      return {};
    }

    return {'Cookie': cookieHeader};
  }

  /// Creates a Cookie header map from cookies.
  static Map<String, String> fromMap(Map<String, String>? cookies) {
    final value = serialize(cookies);

    if (value.isEmpty) {
      return {};
    }

    return {'Cookie': value};
  }

  /// Extracts Set-Cookie values into cookies.
  ///
  /// Supports:
  /// `session=abc; Path=/; HttpOnly`
  static Map<String, String> parseSetCookie(Iterable<String>? headers) {
    if (headers == null) {
      return {};
    }

    final result = <String, String>{};

    for (final header in headers) {
      final index = header.indexOf('=');

      if (index <= 0) {
        continue;
      }

      final end = header.indexOf(';');

      final cookie = end == -1 ? header : header.substring(0, end);

      final separator = cookie.indexOf('=');

      if (separator <= 0) {
        continue;
      }

      final key = cookie.substring(0, separator).trim();
      final value = cookie.substring(separator + 1).trim();

      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  /// Removes surrounding quotes from a cookie value.
  static String unquote(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }

  /// Quotes a cookie value.
  static String quote(String value) {
    if (value.startsWith('"') && value.endsWith('"')) {
      return value;
    }

    return '"$value"';
  }

  /// Encodes a cookie value.
  ///
  /// Uses URI encoding for safe transport.
  static String encodeValue(String value) {
    return Uri.encodeComponent(value);
  }

  /// Decodes a cookie value.
  static String decodeValue(String value) {
    return Uri.decodeComponent(value);
  }

  /// Returns cookie count.
  static int count(String? cookieHeader) {
    return parse(cookieHeader).length;
  }

  /// Returns whether cookie header is empty.
  static bool isEmpty(String? cookieHeader) {
    return parse(cookieHeader).isEmpty;
  }

  /// Returns whether cookie header contains any cookie.
  static bool isNotEmpty(String? cookieHeader) {
    return parse(cookieHeader).isNotEmpty;
  }
}
