/// The one rule for caller-supplied request headers.
///
/// Every package that puts a header on the wire used to carry its own copy of
/// this: one dropped the offender and logged, one threw, two rewrote the value
/// into something the site never issued. Four spellings of the same decision,
/// and the decision itself was wrong in three of them — a header that cannot
/// be sent safely is not a thing to work around quietly, because the one that
/// gets dropped is usually `Authorization` or `Cookie`, and what the caller
/// sees afterwards is an unexplained 403.
///
/// So the rule here is: **send it exactly as given, or fail**. Nothing is
/// substituted and nothing is skipped. [HttpHeaderError] names the offending
/// header, which is the information the caller needs and the only thing that
/// was missing from the silent versions.
final class HttpHeaderError extends ArgumentError {
  /// Creates an error for [headerName].
  HttpHeaderError(this.headerName, this.reason)
    : super('request header "$headerName" cannot be sent: $reason', 'headers');

  /// The name as the caller spelled it.
  final String headerName;

  /// Why it cannot go on the wire.
  final String reason;
}

/// Validates and normalizes request headers.
///
/// Normalization is limited to what cannot change meaning: names are trimmed
/// and lower-cased, and values are trimmed of the optional whitespace around
/// them, because HTTP field names are case-insensitive and field values lose
/// that padding in every parser anyway. Every consumer here (FFmpeg's
/// `-headers`, mpv's `http-header-fields`, ijkplayer's `headers` option,
/// `dart:io`'s HttpHeaders) matches names case-insensitively.
///
/// Values are never rewritten. A value carrying CR, LF or NUL would start a
/// second header line in whichever parser receives it, and replacing the
/// newline with a space would send a cookie or a token the site did not issue.
abstract final class HttpHeaderSanitizer {
  /// Header names FFmpeg, mpv, ijkplayer and `dart:io` all accept.
  static final RegExp _validName = RegExp(r'^[a-z0-9-]+$');

  /// The characters that would let a value forge another header.
  static final RegExp _unsafeValue = RegExp(r'[\r\n\u0000]');

  /// Returns [headers] with lower-cased names, or an empty map when there is
  /// nothing to send.
  ///
  /// Throws [HttpHeaderError] for a header that cannot be sent as-is: an empty
  /// or malformed name, an empty value, or a value carrying a newline. Callers
  /// that treat a header as optional must omit it rather than pass an empty
  /// string — an empty value reaching the wire is indistinguishable from a
  /// credential the caller forgot to fill in.
  static Map<String, String> sanitize(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return <String, String>{};
    }

    final sanitized = <String, String>{};
    for (final entry in headers.entries) {
      final name = entry.key.trim().toLowerCase();
      if (name.isEmpty) {
        throw HttpHeaderError(entry.key, 'the name is empty');
      }
      if (!_validName.hasMatch(name)) {
        throw HttpHeaderError(
          entry.key,
          'the name is not a token (letters, digits and "-" only); sending it '
          'would let one map entry forge additional header lines',
        );
      }

      final value = entry.value.trim();
      if (value.isEmpty) {
        throw HttpHeaderError(entry.key, 'the value is empty');
      }
      if (_unsafeValue.hasMatch(value)) {
        throw HttpHeaderError(
          entry.key,
          'the value contains CR, LF or NUL, which would inject another '
          'header line into the request',
        );
      }

      sanitized[name] = value;
    }
    return sanitized;
  }

  /// Joins [sanitized] into the CRLF-terminated block FFmpeg's `-headers`
  /// option expects, or an empty string when there is nothing to send.
  ///
  /// Takes the output of [sanitize]; joining raw caller input would skip the
  /// validation that is the point of this class.
  static String ffmpegBlock(Map<String, String> sanitized) {
    if (sanitized.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    sanitized.forEach((name, value) => buffer.write('$name: $value\r\n'));
    return buffer.toString();
  }

  /// The `Name: value` lines mpv's `http-header-fields` list takes.
  static List<String> mpvFields(Map<String, String> sanitized) {
    return sanitized.entries.map((entry) => '${entry.key}: ${entry.value}').toList(growable: false);
  }
}
