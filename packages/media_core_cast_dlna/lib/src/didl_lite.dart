import 'package:media_core/casting/cast_media.dart';

/// Builds DIDL-Lite metadata for `SetAVTransportURI`.
///
/// A DLNA renderer is given two things: the URL, and a DIDL-Lite
/// document describing it. Most stock TVs read only `res` (the URL,
/// again, this time with `protocolInfo` so the device can decide
/// whether it can play it) and `dc:title`; everything else here is
/// what a richer renderer uses for its library UI.
abstract final class DidlLite {
  /// Builds the object element for [media].
  ///
  /// `protocolInfo` follows `http-get:{mime}:{dlna-profile}`. The
  /// profile is guessed from the MIME: `*` is legal but many TV
  /// firmwares will refuse a `*` profile they can't match to a
  /// decoder, while `DLNA.ORG_PN=MP3`/`AVI`/none is a hint they do
  /// understand. An unknown MIME still emits a usable `*` line.
  static String build(CastMedia media, {String objectId = '0', String parentID = '-1', bool restricted = true}) {
    final mime = media.mimeType ?? _mimeFromUrl(media.url);
    final profile = _profileFor(mime);
    final protocol = 'http-get:$mime:${profile ?? ''}';

    final builder = StringBuffer()
      ..write('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" ')
      ..write('xmlns:dc="http://purl.org/dc/elements/1.1/" ')
      ..write('xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">')
      ..write('<item id="${_escape(objectId)}" parentID="${_escape(parentID)}" restricted="$restricted">')
      ..write('<dc:title>${_escape(media.title)}</dc:title>')
      ..write('<upnp:class>${_escape(media.objectClass)}</upnp:class>');

    if (media.creator != null && media.creator!.isNotEmpty) {
      builder
        ..write('<dc:creator>${_escape(media.creator!)}</dc:creator>')
        ..write('<upnp:artist>${_escape(media.creator!)}</upnp:artist>');
    }

    if (media.artworkUrl != null) {
      builder.write('<upnp:albumArtURI>${_escape(media.artworkUrl.toString())}</upnp:albumArtURI>');
    }

    builder
      ..write('<res protocolInfo="${_escape(protocol)}"')
      ..write(' size="0"')
      ..write(' mimeType="${_escape(mime)}"')
      ..write('>${_escape(media.url)}</res>')
      ..write('</item></DIDL-Lite>');

    return builder.toString();
  }

  static String _mimeFromUrl(String url) {
    final lower = url.toLowerCase();
    final path = lower.contains('?') ? lower.split('?').first : lower;
    if (path.endsWith('.mp4') || path.endsWith('.m4v')) {
      return 'video/mp4';
    }
    if (path.endsWith('.mkv')) {
      return 'video/x-matroska';
    }
    if (path.endsWith('.webm')) {
      return 'video/webm';
    }
    if (path.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (path.endsWith('.aac') || path.endsWith('.m4a')) {
      return 'audio/aac';
    }
    if (path.endsWith('.ts') || path.endsWith('.m2ts')) {
      return 'video/mp2t';
    }
    if (path.endsWith('.m3u8')) {
      return 'application/vnd.apple.mpegurl';
    }
    return '*';
  }

  static String? _profileFor(String mime) {
    switch (mime) {
      case 'audio/mpeg':
        return 'DLNA.ORG_PN=MP3';
      case 'video/mp4':
        return 'DLNA.ORG_PN=MP4';
      case 'video/mp2t':
        return 'DLNA.ORG_PN=TS';
      default:
        return null;
    }
  }

  static String _escape(String value) {
    return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  }
}
