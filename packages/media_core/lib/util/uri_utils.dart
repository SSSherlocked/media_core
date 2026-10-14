/// Utilities for parsing, validating and manipulating URIs.
abstract final class UriUtils {
  UriUtils._();

  /// Parses URI safely.
  static Uri? parse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return Uri.tryParse(value.trim());
  }

  /// Returns whether value is a valid URI.
  static bool isValid(String? value) {
    return parse(value) != null;
  }

  /// Returns whether URI is HTTP or HTTPS.
  static bool isHttp(String? value) {
    final uri = parse(value);

    if (uri == null) {
      return false;
    }

    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  /// Returns whether URI is HTTPS.
  static bool isHttps(String? value) {
    final uri = parse(value);

    return uri?.scheme == 'https';
  }

  /// Returns whether URI is a network stream URL.
  static bool isNetwork(String? value) {
    final uri = parse(value);

    if (uri == null) {
      return false;
    }

    return switch (uri.scheme.toLowerCase()) {
      'http' || 'https' || 'rtmp' || 'rtsp' || 'udp' || 'tcp' || 'mms' => true,
      _ => false,
    };
  }

  /// Returns URI scheme.
  static String? scheme(String? value) {
    return parse(value)?.scheme;
  }

  /// Returns URI host.
  static String? host(String? value) {
    return parse(value)?.host;
  }

  /// Returns URI port.
  static int? port(String? value) {
    return parse(value)?.port;
  }

  /// Returns URI path.
  static String? path(String? value) {
    return parse(value)?.path;
  }

  /// Returns query parameters.
  static Map<String, String> queryParameters(String? value) {
    return parse(value)?.queryParameters ?? {};
  }

  /// Returns query parameter by name.
  static String? query(String? value, String name) {
    return parse(value)?.queryParameters[name];
  }

  /// Adds or replaces query parameter.
  static String addQuery(String uri, String key, String value) {
    final parsed = parse(uri);

    if (parsed == null) {
      return uri;
    }

    final params = Map<String, String>.from(parsed.queryParameters);

    params[key] = value;

    return parsed.replace(queryParameters: params).toString();
  }

  /// Adds multiple query parameters.
  static String addQueries(String uri, Map<String, String> values) {
    final parsed = parse(uri);

    if (parsed == null) {
      return uri;
    }

    final params = Map<String, String>.from(parsed.queryParameters)..addAll(values);

    return parsed.replace(queryParameters: params).toString();
  }

  /// Removes query parameter.
  static String removeQuery(String uri, String key) {
    final parsed = parse(uri);

    if (parsed == null) {
      return uri;
    }

    final params = Map<String, String>.from(parsed.queryParameters)..remove(key);

    return parsed.replace(queryParameters: params).toString();
  }

  /// Returns file extension from URI path.
  static String? extension(String? value) {
    final path = UriUtils.path(value);

    if (path == null || path.isEmpty) {
      return null;
    }

    final index = path.lastIndexOf('.');

    if (index == -1 || index == path.length - 1) {
      return null;
    }

    return path.substring(index + 1).toLowerCase();
  }

  /// Returns file name from URI path.
  static String? fileName(String? value) {
    final path = UriUtils.path(value);

    if (path == null || path.isEmpty) {
      return null;
    }

    final index = path.lastIndexOf('/');

    if (index == -1) {
      return path;
    }

    return path.substring(index + 1);
  }

  /// Removes URI fragment.
  static String removeFragment(String uri) {
    final parsed = parse(uri);

    if (parsed == null) {
      return uri;
    }

    return parsed.replace(fragment: '').toString();
  }

  /// Removes query parameters.
  static String removeQueryParameters(String uri) {
    final parsed = parse(uri);

    if (parsed == null) {
      return uri;
    }

    return parsed.replace(queryParameters: {}).toString();
  }

  /// Normalizes URI string.
  static String normalize(String value) {
    final uri = parse(value);

    if (uri == null) {
      return value.trim();
    }

    return uri.normalizePath().toString();
  }

  /// Encodes URI component.
  static String encode(String value) {
    return Uri.encodeComponent(value);
  }

  /// Decodes URI component.
  static String decode(String value) {
    return Uri.decodeComponent(value);
  }

  /// Joins base URI and path.
  static String join(String base, String path) {
    final uri = parse(base);

    if (uri == null) {
      return path;
    }

    return uri.resolve(path).toString();
  }

  /// Returns whether URI has credentials.
  static bool hasCredentials(String? value) {
    final uri = parse(value);

    if (uri == null) {
      return false;
    }

    return uri.userInfo.isNotEmpty;
  }

  /// Removes username/password from URI.
  static String removeCredentials(String value) {
    final uri = parse(value);

    if (uri == null) {
      return value;
    }

    return uri.replace(userInfo: '').toString();
  }
}
