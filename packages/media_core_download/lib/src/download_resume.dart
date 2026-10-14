import 'package:media_core_download/src/download_config.dart';

/// What should happen to a partially downloaded file.
enum DownloadResumeDecision {
  /// Nothing to resume: a complete file is already on disk.
  alreadyComplete,

  /// The transfer restarts from zero.
  restart,

  /// The transfer continues from [DownloadResumePlan.startByte].
  resume,
}

/// A resume decision with the numbers it was made from.
final class DownloadResumePlan {
  /// Creates a plan recording the [decision] and the offsets it was made from.
  const DownloadResumePlan({required this.decision, this.startByte = 0, this.verifyBytes = 0, this.reason});

  /// What should happen to the partial file.
  final DownloadResumeDecision decision;

  /// Offset the transfer continues from.
  final int startByte;

  /// Bytes to re-fetch before [startByte] and compare with the local tail.
  final int verifyBytes;

  /// Why the decision was made, for logs and for explaining it to a viewer.
  final String? reason;

  @override
  String toString() => 'DownloadResumePlan(${decision.name}, from $startByte${reason == null ? '' : ', $reason'})';
}

/// Decides how to continue a partial download.
///
/// Ported from the reference implementation's resume rule, which is the part
/// worth copying: a partial file is never trusted just because it exists. The
/// transfer restarts [DownloadConfig.verifyTailBytes] before the end and
/// compares those bytes with what is on disk ([tailMatches]), so a file that is
/// not actually a prefix of the remote one — a different quality, a replaced
/// file, a corrupt write — is caught before it is appended to.
///
/// Without that check the failure mode is the worst kind: the download "succeeds"
/// and the file plays up to exactly the point where the mismatch is.
final class DownloadResumePlanner {
  /// Creates a planner that applies [config]'s resume tunables.
  const DownloadResumePlanner({this.config = DownloadConfig.defaults});

  /// Tunables.
  final DownloadConfig config;

  /// The plan for a partial file.
  ///
  /// [remoteBytes] is the remote size when the server told us; `null` means it
  /// did not, in which case a known partial size is still resumable but cannot
  /// be checked for completeness.
  DownloadResumePlan plan({required int localBytes, required int? remoteBytes, required bool serverAcceptsRanges}) {
    if (localBytes < 0) {
      throw ArgumentError.value(localBytes, 'localBytes', 'Byte count cannot be negative');
    }

    if (localBytes == 0) {
      return const DownloadResumePlan(decision: DownloadResumeDecision.restart, reason: 'nothing on disk');
    }

    if (remoteBytes != null && remoteBytes > 0) {
      if (localBytes == remoteBytes) {
        return const DownloadResumePlan(
          decision: DownloadResumeDecision.alreadyComplete,
          reason: 'the file is already the same size as the remote one',
        );
      }
      if (localBytes > remoteBytes) {
        return const DownloadResumePlan(
          decision: DownloadResumeDecision.restart,
          reason: 'the local file is larger than the remote one, so it belongs to something else',
        );
      }
    }

    if (!serverAcceptsRanges && !config.forceResume) {
      return const DownloadResumePlan(
        decision: DownloadResumeDecision.restart,
        reason: 'the server did not offer byte ranges',
      );
    }

    final verify = config.verifyTailBytes;
    if (verify <= 0 || localBytes < verify) {
      // Too little on disk to verify: restarting costs less than one bad file.
      return DownloadResumePlan(
        decision: DownloadResumeDecision.restart,
        reason: verify <= 0
            ? 'tail verification is disabled'
            : 'only $localBytes bytes on disk, less than the $verify needed to verify them',
      );
    }

    return DownloadResumePlan(
      decision: DownloadResumeDecision.resume,
      startByte: localBytes - verify,
      verifyBytes: verify,
      reason: 'verifying the last $verify bytes before continuing',
    );
  }

  /// Whether the bytes at the resume offset still match what is on disk.
  ///
  /// [localTail] is what the partial file already holds at
  /// [DownloadResumePlan.startByte]; [remoteTail] is the same range fetched
  /// again. They must be identical for the transfer to continue.
  bool tailMatches({required List<int> localTail, required List<int> remoteTail}) {
    if (localTail.length != remoteTail.length || localTail.isEmpty) {
      return false;
    }
    for (var index = 0; index < localTail.length; index++) {
      if (localTail[index] != remoteTail[index]) {
        return false;
      }
    }
    return true;
  }
}
