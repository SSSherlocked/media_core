/// Playable input pipeline for media_core.
///
/// Live providers hand out sources that a player cannot open as they are: HLS
/// manifests whose children are bare names, absolute-path children, signed URLs
/// that expire mid-stream, per-child tokens, cookies issued with the manifest,
/// containers the player's FFmpeg cannot parse. Without a home for that work
/// every host grows its own relays and its own branching.
///
/// This package owns the decision and the two mechanisms:
///
/// ```dart
/// final plan = resolveIngestPlan(needs: <IngestNeed>{IngestNeed.relativeChildren});
/// switch (plan.strategy) {
///   case IngestStrategy.direct:
///     player.open(Media(source.toString()));
///   case IngestStrategy.manifestRelay:
///     final relay = await LoopbackIngestRelay.start(source: source, headers: headers);
///     player.open(Media(relay.inputUri.toString()));
///   case IngestStrategy.ffmpegRelay:
///     final relay = await FfmpegIngestRelay.start(source: source, executor: executor);
///     player.open(Media(relay.inputUri.toString()));
/// }
/// ```
///
/// The direct path stays the default: a relay costs a process, a port and a
/// second or two of startup, so only a declared [IngestNeed] moves a source.
library;

import 'package:media_core_ingest/src/ingest_plan.dart' show IngestNeed;

export 'src/ffmpeg_ingest_relay.dart';
export 'src/hls_manifest_kind.dart';
export 'src/hls_session_cookies.dart';
export 'src/hls_source_query_policy.dart';
export 'src/ingest_ffmpeg.dart';
export 'src/ingest_plan.dart';
export 'src/loopback_ingest_relay.dart';
