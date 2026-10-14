import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_headers.dart';
import 'package:media_core/source/source_media_type.dart';
import 'package:media_core/source/source_protocol.dart';
import 'package:media_core/source/source_type.dart';

/// Builds sample [PlayerSource] values for tests.
///
/// Sources built here are fully valid unless stated otherwise
/// in the method documentation.
final class TestSourceFactory {
  const TestSourceFactory._();

  /// A standard http mp4 source.
  static PlayerSource httpMp4({
    String id = 'src-http-mp4',
    String url = 'https://example.com/video.mp4',
    Map<String, String> headers = const {'user-agent': 'media_core_test'},
  }) {
    return PlayerSource(
      id: SourceId(id),
      uri: Uri.parse(url),
      type: SourceType.remote,
      protocol: SourceProtocol.https,
      mediaType: SourceMediaType.video,
      format: SourceFormat.mp4,
      headers: SourceHeaders(headers),
      title: 'HTTP MP4 sample',
    );
  }

  /// An http mp3 audio source.
  static PlayerSource httpAudio({String id = 'src-http-audio', String url = 'https://example.com/audio.mp3'}) {
    return PlayerSource(
      id: SourceId(id),
      uri: Uri.parse(url),
      type: SourceType.remote,
      protocol: SourceProtocol.https,
      mediaType: SourceMediaType.audio,
      format: SourceFormat.mp3,
    );
  }

  /// An HLS live source.
  static PlayerSource hlsLive({String id = 'src-hls-live', String url = 'https://example.com/live/index.m3u8'}) {
    return PlayerSource(
      id: SourceId(id),
      uri: Uri.parse(url),
      type: SourceType.live,
      protocol: SourceProtocol.hls,
      mediaType: SourceMediaType.video,
      format: SourceFormat.m3u8,
    );
  }

  /// A DASH source.
  static PlayerSource dash({String id = 'src-dash', String url = 'https://example.com/stream.mpd'}) {
    return PlayerSource(
      id: SourceId(id),
      uri: Uri.parse(url),
      type: SourceType.stream,
      protocol: SourceProtocol.dash,
      mediaType: SourceMediaType.video,
      format: SourceFormat.mpd,
    );
  }

  /// An RTMP live source.
  static PlayerSource rtmp({String id = 'src-rtmp', String url = 'rtmp://example.com/live/stream'}) {
    return PlayerSource(id: SourceId(id), uri: Uri.parse(url), type: SourceType.live, protocol: SourceProtocol.rtmp);
  }

  /// A local file source.
  static PlayerSource file({String id = 'src-file', String path = '/tmp/video.mp4'}) {
    return PlayerSource(
      id: SourceId(id),
      uri: Uri.file(path),
      type: SourceType.file,
      protocol: SourceProtocol.file,
      mediaType: SourceMediaType.video,
      format: SourceFormat.mp4,
    );
  }

  /// An asset source.
  static PlayerSource asset({String id = 'src-asset', String path = 'assets/sample.mp4'}) {
    return PlayerSource(
      id: SourceId(id),
      uri: Uri.parse('asset:///$path'),
      type: SourceType.asset,
      protocol: SourceProtocol.asset,
      mediaType: SourceMediaType.video,
    );
  }

  /// An unknown source, invalid for playback.
  static PlayerSource unknown() => PlayerSource.unknown();

  /// All valid sample sources.
  static List<PlayerSource> all() {
    return [httpMp4(), httpAudio(), hlsLive(), dash(), rtmp(), file(), asset()];
  }
}
