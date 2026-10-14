import 'package:flutter/foundation.dart' show immutable;
import 'package:media_core/media_core.dart' show PlayerSource;

/// One entry of a playback list.
///
/// [id] is what progress is remembered by, and it is deliberately separate
/// from the source: the same stream can appear twice in a list under different
/// ids (a re-watch entry, a different room number for the same feed), and the
/// two must not share a resume position. Conversely a source whose URL is
/// rotated by the site keeps one id, so its progress survives the rotation.
@immutable
final class PlaybackListItem {
  /// Creates a list entry identified by [id], playing [source], optionally
  /// labelled [title].
  const PlaybackListItem({required this.id, required this.source, this.title});

  /// Stable identity used for progress memory.
  final String id;

  /// Media to play.
  final PlayerSource source;

  /// Optional label for the host's UI.
  final String? title;

  @override
  bool operator ==(Object other) => identical(this, other) || (other is PlaybackListItem && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PlaybackListItem($id${title == null ? '' : ', $title'})';
}
