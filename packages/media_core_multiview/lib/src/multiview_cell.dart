import 'package:media_core/media_core.dart' show PlayerSource;
import 'package:media_core_danmaku/media_core_danmaku.dart' show DanmakuOverlaySession;

/// What a cell is doing.
enum MultiviewCellStatus {
  /// No room assigned.
  empty,

  /// Opening its source.
  starting,

  /// Playing.
  playing,

  /// Paused by the host; the stall watchdog skips it.
  paused,

  /// The room is known to be offline.
  ///
  /// A business state, not a failure: the platform said the stream is not
  /// running, so nothing is wrong with this app and a restarted player would
  /// still find nothing.
  offline,

  /// Restarting after a stall.
  recovering,

  /// Failed; no further automatic attempts.
  failed,
}

/// Produces a fresh source for one whose signed URL has expired.
///
/// Returning null keeps the current source; throwing fails the open.
typedef MultiviewSourceRenew = Future<MultiviewCellSource?> Function(MultiviewCellSource current);

/// Why a cell failed.
enum MultiviewCellFailureKind {
  /// The source could not be resolved.
  resolveFailure,

  /// The source resolved but the player could not open it.
  startFailure,

  /// The player opened it and then stopped making progress.
  stallFailure,
}

/// One cell's failure, with the attempt it happened on.
final class MultiviewCellFailure {
  /// Creates a failure of [kind] with [message], on restart [attempt], caused by [cause].
  const MultiviewCellFailure({required this.kind, required this.message, this.attempt = 1, this.cause});

  /// Why the cell failed.
  final MultiviewCellFailureKind kind;

  /// Human-readable reason shown by the host.
  final String message;

  /// Which restart attempt this failure belongs to.
  final int attempt;

  /// The underlying error, when one was caught.
  final Object? cause;

  @override
  String toString() => 'MultiviewCellFailure(${kind.name}, attempt $attempt: $message)';
}

/// What a cell is playing.
final class MultiviewCellSource {
  /// Creates a cell source with its playback metadata and renewal hook.
  const MultiviewCellSource({
    required this.source,
    this.title,
    this.roomId,
    this.qualityLabel,
    this.isLive = true,
    this.expiresAt,
    this.renew,
  });

  /// Media to open.
  final PlayerSource source;

  /// Display name for the cell.
  final String? title;

  /// Room identity, for hosts that name cells by room.
  final String? roomId;

  /// Quality label the source was resolved at, for the cell's overlay text.
  final String? qualityLabel;

  /// Whether the room is live. `false` marks the cell [MultiviewCellStatus.offline].
  final bool isLive;

  /// When the source's URL stops being valid, for signed URLs.
  final DateTime? expiresAt;

  /// Produces a fresh source once [expiresAt] has passed.
  ///
  /// The wall invokes it before every (re)open of an expired source: stall
  /// restarts, quality switches and playlist advances all go through it.
  /// Returning null keeps the current source; throwing fails the open.
  final MultiviewSourceRenew? renew;

  /// Whether the source's signed URL is no longer valid at [now].
  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  @override
  String toString() => 'MultiviewCellSource(${title ?? roomId ?? source.uri})';
}

/// One cell of the wall.
///
/// Mutable and owned by the controller: a cell changes status, quality and
/// focus many times while the wall is up, and copying it on every change would
/// make the host's rebuild path more expensive than the change.
final class MultiviewCell {
  /// Creates the cell at grid [index] with its initial state.
  MultiviewCell({
    required this.index,
    this.source,
    this.status = MultiviewCellStatus.empty,
    this.failure,
    this.playerId,
    this.restarts = 0,
    this.qualityLabel,
    this.hasVideoFocus = false,
    this.hasAudioFocus = false,
  });

  /// Position in the grid.
  final int index;

  /// What the cell plays, or `null` when empty.
  MultiviewCellSource? source;

  /// Current status.
  MultiviewCellStatus status;

  /// Last failure, cleared on a successful start.
  MultiviewCellFailure? failure;

  /// Identity of the player this cell owns, when one is open.
  String? playerId;

  /// How many times this cell has been restarted.
  int restarts;

  /// Quality currently playing.
  String? qualityLabel;

  /// Whether this cell is the wall's focused picture.
  bool hasVideoFocus;

  /// Whether this cell is the one that is audible.
  bool hasAudioFocus;

  /// Per-cell danmaku, created lazily.
  ///
  /// Each cell gets its own overlay session: a danmaku queue is per surface,
  /// and sharing one would let a wall cell's backlog appear on another.
  DanmakuOverlaySession? danmaku;

  /// Whether no source is assigned to this cell.
  bool get isEmpty => status == MultiviewCellStatus.empty;

  /// Whether this cell is currently playing.
  bool get isPlaying => status == MultiviewCellStatus.playing;

  /// Whether this cell is paused by the host.
  bool get isPaused => status == MultiviewCellStatus.paused;

  /// Whether the cell is in a state that can still become playing.
  bool get isActive =>
      status == MultiviewCellStatus.starting ||
      status == MultiviewCellStatus.playing ||
      status == MultiviewCellStatus.recovering;

  /// Whether the cell should be retried automatically.
  bool get canRecover => !isPlaying && status != MultiviewCellStatus.offline && status != MultiviewCellStatus.empty;

  @override
  String toString() => 'MultiviewCell($index, ${status.name}${source == null ? '' : ', $source'})';
}
