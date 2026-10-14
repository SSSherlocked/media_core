import 'package:media_core/source/library.dart' show SourceFormat, SourceType;

/// Describes the protocol or transport used to access a media source.
///
/// [SourceProtocol] describes how a source is accessed. It is intentionally
/// separate from [SourceType] and [SourceFormat]:
///
/// - [SourceType] describes the general source category.
/// - [SourceProtocol] describes how the source is accessed.
/// - [SourceFormat] describes the media/container format.
///
/// For example, an HLS source may have:
///
/// - type: [SourceType.live]
/// - protocol: [SourceProtocol.hls]
/// - format: [SourceFormat.m3u8]
enum SourceProtocol {
  /// Unknown or not yet determined.
  unknown,

  /// HTTP.
  http,

  /// HTTPS.
  https,

  /// HTTP Live Streaming.
  hls,

  /// MPEG-DASH.
  dash,

  /// Real-Time Messaging Protocol.
  rtmp,

  /// Real Time Streaming Protocol.
  rtsp,

  /// WebRTC.
  webrtc,

  /// User Datagram Protocol based media transport.
  udp,

  /// Local file access.
  file,

  /// Application asset access.
  asset,

  /// Application-defined protocol.
  custom;

  /// Attempts to infer a protocol from a URI scheme.
  ///
  /// Lives on the enum rather than in the extension so callers reach it as
  /// `SourceProtocol.fromScheme(...)` — a source builder has to be able to
  /// declare a protocol without importing an extension by name.
  static SourceProtocol fromScheme(String? scheme) {
    final value = scheme?.trim().toLowerCase();

    switch (value) {
      case 'http':
        return SourceProtocol.http;

      case 'https':
        return SourceProtocol.https;

      case 'hls':
        return SourceProtocol.hls;

      case 'dash':
        return SourceProtocol.dash;

      case 'rtmp':
      case 'rtmps':
        return SourceProtocol.rtmp;

      case 'rtsp':
      case 'rtsps':
        return SourceProtocol.rtsp;

      case 'webrtc':
        return SourceProtocol.webrtc;

      case 'udp':
        return SourceProtocol.udp;

      case 'file':
        return SourceProtocol.file;

      case 'asset':
        return SourceProtocol.asset;

      default:
        return SourceProtocol.unknown;
    }
  }
}

/// Extensions for [SourceProtocol].
extension SourceProtocolX on SourceProtocol {
  /// Whether this protocol is unknown.
  bool get isUnknown => this == SourceProtocol.unknown;

  /// Whether this protocol is known.
  bool get isKnown => this != SourceProtocol.unknown;

  /// Whether this protocol uses HTTP semantics.
  bool get isHttp {
    return this == SourceProtocol.http || this == SourceProtocol.https;
  }

  /// Whether this protocol is HTTPS.
  bool get isHttps => this == SourceProtocol.https;

  /// Whether this protocol is HLS.
  bool get isHls => this == SourceProtocol.hls;

  /// Whether this protocol is DASH.
  bool get isDash => this == SourceProtocol.dash;

  /// Whether this protocol is RTMP.
  bool get isRtmp => this == SourceProtocol.rtmp;

  /// Whether this protocol is RTSP.
  bool get isRtsp => this == SourceProtocol.rtsp;

  /// Whether this protocol is WebRTC.
  bool get isWebRtc => this == SourceProtocol.webrtc;

  /// Whether this protocol is UDP-based.
  bool get isUdp => this == SourceProtocol.udp;

  /// Whether this protocol accesses a local file.
  bool get isFile => this == SourceProtocol.file;

  /// Whether this protocol accesses an application asset.
  bool get isAsset => this == SourceProtocol.asset;

  /// Whether this is an application-defined protocol.
  bool get isCustom => this == SourceProtocol.custom;

  /// Whether this protocol represents a local source.
  bool get isLocal {
    return this == SourceProtocol.file || this == SourceProtocol.asset;
  }

  /// Whether this protocol represents a network source.
  bool get isNetwork {
    switch (this) {
      case SourceProtocol.http:
      case SourceProtocol.https:
      case SourceProtocol.hls:
      case SourceProtocol.dash:
      case SourceProtocol.rtmp:
      case SourceProtocol.rtsp:
      case SourceProtocol.webrtc:
      case SourceProtocol.udp:
        return true;

      case SourceProtocol.unknown:
      case SourceProtocol.file:
      case SourceProtocol.asset:
      case SourceProtocol.custom:
        return false;
    }
  }

  /// Whether this protocol is connection-oriented.
  bool get isConnectionOriented {
    switch (this) {
      case SourceProtocol.http:
      case SourceProtocol.https:
      case SourceProtocol.hls:
      case SourceProtocol.dash:
      case SourceProtocol.rtmp:
      case SourceProtocol.rtsp:
      case SourceProtocol.webrtc:
        return true;

      case SourceProtocol.udp:
      case SourceProtocol.file:
      case SourceProtocol.asset:
      case SourceProtocol.unknown:
      case SourceProtocol.custom:
        return false;
    }
  }

  /// Whether this protocol is manifest-based.
  bool get isManifest {
    return this == SourceProtocol.hls || this == SourceProtocol.dash;
  }

  /// Whether this protocol is commonly used for live playback.
  bool get isLive {
    switch (this) {
      case SourceProtocol.hls:
      case SourceProtocol.rtmp:
      case SourceProtocol.rtsp:
      case SourceProtocol.webrtc:
      case SourceProtocol.udp:
        return true;

      case SourceProtocol.unknown:
      case SourceProtocol.http:
      case SourceProtocol.https:
      case SourceProtocol.dash:
      case SourceProtocol.file:
      case SourceProtocol.asset:
      case SourceProtocol.custom:
        return false;
    }
  }

  /// Returns the URI schemes commonly associated with this protocol.
  List<String> get schemes {
    switch (this) {
      case SourceProtocol.http:
        return const ['http'];

      case SourceProtocol.https:
        return const ['https'];

      case SourceProtocol.hls:
        return const ['hls', 'http', 'https'];

      case SourceProtocol.dash:
        return const ['dash', 'http', 'https'];

      case SourceProtocol.rtmp:
        return const ['rtmp', 'rtmps'];

      case SourceProtocol.rtsp:
        return const ['rtsp', 'rtsps'];

      case SourceProtocol.webrtc:
        return const ['webrtc'];

      case SourceProtocol.udp:
        return const ['udp'];

      case SourceProtocol.file:
        return const ['file'];

      case SourceProtocol.asset:
        return const ['asset'];

      case SourceProtocol.unknown:
      case SourceProtocol.custom:
        return const [];
    }
  }

  /// Returns the stable string representation of this protocol.
  String get value => name;
}
