/// Declared format and protocol coverage of the available backends.
///
/// These sets are the values handed to
/// [PlayerAdapterCapabilities.supportedFormats] and
/// [PlayerAdapterCapabilities.supportedProtocols]. They are what
/// `PlayerAdapterSelector` scores a source against, so an entry here is
/// worth real points: protocol +40, format +30, live +10 on top of the
/// registration priority.
///
/// ## What the entries are matched against
///
/// Entries are written as file extensions and URI schemes, which is how
/// engine support is normally documented, and matching understands both
/// spellings:
///
/// - a **format** entry matches either the source's `SourceFormat` name
///   (`mpegts`, `m3u8`, `mp4`, ...) or the extension of its URI path
///   (`ts`, `m2ts`, `m3u8`, ...). Both spellings are needed: `SourceFormat`
///   models a subset of the extensions (`.ts` is `SourceFormat.mpegTs`),
///   and a container the enum does not model at all (`rmvb`, `ape`, `nut`)
///   can only be matched by its extension;
/// - a **protocol** entry matches either the source's `SourceProtocol` name
///   (`https`, `rtmp`, ...) or the URI scheme (`rtmps`, `srt`, `ftp`).
///   `SourceProtocol` has no value for every scheme an engine accepts.
///
/// So `ts` and `mpegts` are both correct spellings of MPEG-TS, and listing
/// both is harmless.
///
/// One known approximation: [SourceProtocol.fromScheme] folds the TLS
/// variants onto their plain value (`rtmps` -> `rtmp`, `rtsps` -> `rtsp`),
/// so a backend that declares `rtmp` also matches an `rtmps://` source.
/// Do not rely on a TLS variant entry to exclude a backend.
///
/// ## What belongs here
///
/// Only what the engine can be relied on to handle. A missing entry is not
/// neutral: it costs 30 points and can hand a source to a lower-priority
/// backend, while an entry that overstates the engine costs a failed open
/// and a recovery escalation. When in doubt, leave it out.
///
/// Subtitles (`vtt`, `srt`, `ass`) are not listed: they describe sidecar
/// tracks, not the media source being selected.
library;

import 'package:media_core/media_core.dart' show PlayerAdapterCapabilities, SourceProtocol;

/// Coverage of media_kit (libmpv / FFmpeg).
///
/// Verified against libmpv's demuxer set: FFmpeg carries the containers,
/// audio codecs and protocols below. `rm`/`rmvb`/`ape`/`amr`/`wma` are
/// legacy decoders — present in the FFmpeg builds mpv ships, but the first
/// thing dropped by a custom `--disable-everything` build.
abstract final class MediaKitFormats {
  /// Containers, manifests and elementary streams libmpv opens.
  static const Set<String> supportedFormats = {
    // Common video containers.
    'mp4', 'm4v', 'mov', 'mkv', 'webm',
    'avi', 'wmv', 'flv', 'f4v', '3gp',
    '3g2', 'mpg', 'mpeg', 'm2v', 'm2ts',
    'mts', 'vob', 'ts', 'mxf', 'asf',
    'rm', 'rmvb', 'ogv',

    // Adaptive streaming manifests.
    //
    // HLS and DASH only. `ism`/`isml`/`ismc`/`f4m` are Smooth Streaming
    // manifests and FFmpeg has no demuxer for them, so they were removed:
    // declaring them only bought a phantom format match.
    'm3u', 'm3u8', 'mpd',

    // Audio containers and codecs.
    'mp3', 'aac', 'm4a', 'ac3', 'eac3',
    'dts', 'flac', 'wav', 'ogg', 'opus',
    'oga', 'wma', 'ape', 'amr', 'aiff',
    'mka', 'm4b', 'ra',

    // MPEG program/transport stream variants.
    'm2p', 'm2t', 'mpe', 'm1v', 'm1a',
    'mpegts',

    // Other containers FFmpeg demuxes.
    'nut', 'y4m', 'ivf',

    // Raw elementary streams.
    //
    // Annex-B video streams are openable as files; `av1`/`vp8`/`vp9` were
    // removed because there is no such extension to match — those codecs
    // reach the player inside a container, or as `.ivf`, which is listed.
    'h264', 'h265', 'hevc', '264', '265',
  };

  /// URI schemes mpv accepts.
  static const Set<String> supportedProtocols = {
    'http',
    'https',
    'hls',
    'dash',
    'rtmp',
    'rtmps',
    'rtsp',
    'rtsps',
    'srt',
    'udp',
    'rtp',
    'tcp',
    'ftp',
    'ftps',
    // Local playback. Listed because `file://` and asset sources are
    // scored on the same scale, and their absence silently cost them the
    // protocol bonus.
    'file',
    'asset',
  };
}

/// Coverage of IJKPlayer (FFmpeg inside a prebuilt `.so`).
///
/// Same FFmpeg backing as media_kit, so the containers match. Two
/// differences are deliberate: `mxf` is left out because ijkplayer builds
/// commonly trim it, and `srt`/`ftp`/`ftps` are left out of the protocol
/// set because they depend on optional libraries in the shipped binary
/// rather than on the demuxer set.
abstract final class IjkFormats {
  /// Containers, manifests and elementary streams ijkplayer opens.
  static const Set<String> supportedFormats = {
    // Common video containers.
    'mp4', 'm4v', 'mov', 'mkv', 'webm',
    'avi', 'wmv', 'flv', 'f4v', '3gp',
    '3g2', 'mpg', 'mpeg', 'm2v', 'm2ts',
    'mts', 'vob', 'ts', 'asf',
    'rm', 'rmvb', 'ogv',

    // Adaptive streaming manifests. HLS and DASH only, see [MediaKitFormats].
    'm3u', 'm3u8', 'mpd',

    // Audio containers and codecs.
    'mp3', 'aac', 'm4a', 'ac3', 'eac3',
    'dts', 'flac', 'wav', 'ogg', 'opus',
    'oga', 'wma', 'ape', 'amr', 'aiff',
    'mka', 'ra',

    // MPEG program/transport stream variants.
    'm2p', 'm2t', 'mpe', 'm1v', 'm1a',
    'mpegts',

    // Other containers FFmpeg demuxes.
    'nut', 'y4m', 'ivf',

    // Raw elementary streams.
    'h264', 'h265', 'hevc', '264', '265',
  };

  /// URI schemes ijkplayer accepts.
  static const Set<String> supportedProtocols = {
    'http',
    'https',
    'hls',
    'dash',
    'rtmp',
    'rtmps',
    'rtsp',
    'rtsps',
    'udp',
    'rtp',
    'tcp',
    'file',
    'asset',
  };
}

/// Coverage of better_player_plus (AndroidX Media3 / ExoPlayer).
///
/// Verified against Media3's extractor set, which is narrower than
/// FFmpeg's and — unlike FFmpeg — cannot be extended by a build flag. The
/// entries that were removed and the reasons:
///
/// - `wmv`: Media3 has no ASF demuxer, so Windows Media files never open.
/// - `rtmps`, `rtsps`, `srt`, `tcp`, `ftp`, `ftps`: Media3's data sources
///   cover HTTP(S), file, RTSP, RTMP (without TLS) and UDP/RTP; there is no
///   SRT, FTP or HTTP-over-TLS-variant data source.
/// - `asset`: this adapter maps assets to `null` on purpose (the installed
///   better_player_plus exposes no asset data-source type).
/// What remains is a container list, not a codec list: Media3 extracts
/// `ac3`/`eac3`/`flac`/`opus`, but whether a device can *decode* them is a
/// separate question the declaration cannot answer.
abstract final class BetterPlayerFormats {
  /// Containers and manifests better_player_plus opens.
  static const Set<String> supportedFormats = {
    // Common video containers.
    'mp4',
    'm4v',
    'mov',
    'mkv',
    'webm',
    'avi',
    'f4v',
    '3gp',
    '3g2',
    'mpg',
    'mpeg',
    'ts',
    'm2ts',
    'mts',
    'mpegts',

    // Adaptive streaming manifests.
    'm3u8',
    'mpd',

    // Audio containers and codecs.
    'mp3',
    'aac',
    'm4a',
    'ac3',
    'eac3',
    'wav',
    'ogg',
    'opus',
    'flac',
  };

  /// URI schemes better_player_plus accepts.
  static const Set<String> supportedProtocols = {
    'http',
    'https',
    'hls',
    'dash',
    'rtmp',
    'rtsp',
    // UDP/RTP are reachable only through the RTSP data source, which is
    // still the path an `udp://` source takes here.
    'udp',
    'rtp',
    'file',
  };
}

/// Coverage of fvp (libmdk).
///
/// libmdk bundles its own FFmpeg with a broad demuxer set, so the container
/// list is intended to cover common media formats supported by media_kit.
/// The protocol set is deliberately narrower: the fvp adapter's former built-in preset (now removed; the caller owns the whitelist)
/// installs a protocol whitelist that does not enable `srt`, `ftp` or `ftps`,
/// and declaring a scheme the adapter's own whitelist blocks would only win
/// a source it then fails to open.
abstract final class FvpFormats {
  /// Containers, manifests and elementary streams libmdk opens.
  static const Set<String> supportedFormats = {
    // Common video containers.
    'mp4', 'm4v', 'mov', 'mkv', 'webm',
    'avi', 'wmv', 'flv', 'f4v', '3gp',
    '3g2', 'mpg', 'mpeg', 'm2v', 'm2ts',
    'mts', 'vob', 'ts', 'mxf', 'asf',
    'rm', 'rmvb', 'ogv',

    // Adaptive streaming manifests and segments.
    'm3u', 'm3u8', 'mpd', 'm4s',

    // Audio containers and codecs.
    'mp3', 'aac', 'm4a', 'ac3', 'eac3',
    'dts', 'flac', 'wav', 'ogg', 'opus',
    'oga', 'wma', 'ape', 'amr', 'aiff',
    'mka', 'm4b', 'ra',

    // MPEG program/transport stream variants.
    'm2p', 'm2t', 'mpe', 'm1v', 'm1a',
    'mpegts',

    // Other containers FFmpeg demuxes.
    'nut', 'y4m', 'ivf',

    // Raw elementary streams.
    'h264', 'h265', 'hevc', '264', '265',
  };

  /// URI schemes libmdk accepts with this adapter's protocol whitelist.
  static const Set<String> supportedProtocols = {
    'http',
    'https',
    'hls',
    'dash',
    'rtmp',
    'rtmps',
    'rtsp',
    'rtsps',
    'udp',
    'rtp',
    'tcp',
    'file',
    'asset',
  };
}
