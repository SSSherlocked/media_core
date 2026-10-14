import 'dart:convert';

/// What a manifest's children look like on the wire.
///
/// A player resolves a child URI against the manifest URL. When the manifest
/// only carries bare names (`media.95.mp4`) or absolute paths (`/a/b.ts`), that
/// resolution is the only thing keeping the child reachable - and when the base
/// is lost on the way to the demuxer, the child turns into a local path
/// (`\tc.livehls\...`). Counting the forms is how a host decides whether the
/// tree has to be rewritten before the player ever sees it, without knowing
/// anything about the provider.
final class HlsManifestKind {
  /// Creates a manifest summary from the per-form child counts.
  const HlsManifestKind({
    required this.childCount,
    required this.relativeChildren,
    required this.absolutePathChildren,
    required this.schemeRelativeChildren,
    required this.absoluteChildren,
  });

  /// Plain URI lines (media segments and nested playlists).
  final int childCount;

  /// `media.95.mp4`
  final int relativeChildren;

  /// `/tc.livehls/v1/.../media.95.mp4`
  final int absolutePathChildren;

  /// `//host/path`
  final int schemeRelativeChildren;

  /// `https://host/path`, already unambiguous.
  final int absoluteChildren;

  /// Children that only work while the reader still knows the manifest URL.
  int get childrenNeedingBase => relativeChildren + absolutePathChildren + schemeRelativeChildren;

  /// Whether the manifest must be rewritten over loopback before playback.
  bool get requiresRewrite => childrenNeedingBase > 0;

  /// One line for logs and diagnostics.
  String describe() =>
      'children=$childCount absolute=$absoluteChildren '
      'relative=$relativeChildren absolutePath=$absolutePathChildren schemeRelative=$schemeRelativeChildren';

  @override
  String toString() => 'HlsManifestKind(${describe()})';
}

/// Classifies the children of one HLS manifest body.
///
/// Attribute URIs (`#EXT-X-KEY:URI="key.bin"`, `#EXT-X-MAP:...`) count as
/// children too: an encrypted or fMP4 stream fails the same way, one step later.
HlsManifestKind classifyHlsManifest(String body) {
  var childCount = 0;
  var relative = 0;
  var absolutePath = 0;
  var schemeRelative = 0;
  var absolute = 0;

  void count(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    childCount++;
    final uri = Uri.tryParse(value);
    if (uri == null) {
      relative++;
      return;
    }
    if (uri.hasScheme) {
      absolute++;
      return;
    }
    if (value.startsWith('//')) {
      schemeRelative++;
      return;
    }
    if (value.startsWith('/')) {
      absolutePath++;
      return;
    }
    relative++;
  }

  for (final line in const LineSplitter().convert(body)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) {
      for (final match in _uriAttribute.allMatches(line)) {
        count(match.group(1)!);
      }
      continue;
    }
    count(trimmed);
  }

  return HlsManifestKind(
    childCount: childCount,
    relativeChildren: relative,
    absolutePathChildren: absolutePath,
    schemeRelativeChildren: schemeRelative,
    absoluteChildren: absolute,
  );
}

final RegExp _uriAttribute = RegExp('URI="([^"]+)"', caseSensitive: false);
