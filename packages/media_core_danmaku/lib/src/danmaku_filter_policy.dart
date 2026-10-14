import 'package:media_core_danmaku/src/danmaku_message.dart';

/// Viewer-level suppression rules applied to incoming chat.
///
/// Where the other filters in this module remove *duplicates*, this one
/// removes *senders and words* the viewer asked never to see. It is a pure
/// policy object: it holds no timers, no memory of past messages and no
/// connection state, so the same instance can be shared by several rooms.
///
/// Normalization happens once, here, on construction: entries are trimmed,
/// lowercased and emptied out. Matching is therefore a plain lookup and a
/// plain substring scan, and it is case-insensitive for free. A caller
/// updating the lists constructs a new policy rather than mutating this one,
/// which keeps an in-flight message comparing against one consistent rule set.
final class DanmakuFilterPolicy {
  /// Normalizes [blockedUsers] and [blockedKeywords] once — trim, lowercase,
  /// drop empties — so matching is a plain lookup and substring scan.
  DanmakuFilterPolicy({Iterable<String> blockedUsers = const [], Iterable<String> blockedKeywords = const []})
    : blockedUsers = _normalizeUsers(blockedUsers),
      blockedKeywords = _normalizeKeywords(blockedKeywords);

  /// Const constructor for [none]; the normalizing constructor handles the
  /// public shape.
  const DanmakuFilterPolicy.constant({this.blockedUsers = const <String>{}, this.blockedKeywords = const <String>[]});

  /// Empty policy: nothing is suppressed.
  static const DanmakuFilterPolicy none = DanmakuFilterPolicy.constant();

  /// Lowercased display names that are always suppressed.
  ///
  /// Keyed on [DanmakuMessage.userName] because that is what viewers block —
  /// they see a name, not a user id. A viewer renaming themselves therefore
  /// escapes the block, which is the accepted trade-off: keying on ids would
  /// require every platform to expose one.
  final Set<String> blockedUsers;

  /// Lowercased substrings; a message containing any of them is suppressed.
  final List<String> blockedKeywords;

  /// Whether this policy can suppress anything at all.
  bool get isEmpty => blockedUsers.isEmpty && blockedKeywords.isEmpty;

  /// Whether [message] passes the policy.
  bool allows(DanmakuMessage message) => evaluate(message).allowed;

  /// Classifies why [message] would be suppressed.
  ///
  /// Callers that only need the verdict use [allows]; this exists so a host
  /// can explain a suppression (diagnostics, "show blocked" affordances)
  /// without re-implementing the rules.
  DanmakuFilterDecision evaluate(DanmakuMessage message) {
    if (isEmpty) return const DanmakuFilterDecision.allowed();

    final user = message.userName.trim().toLowerCase();
    if (user.isNotEmpty && blockedUsers.contains(user)) {
      return const DanmakuFilterDecision.rejected(DanmakuFilterReason.blockedUser);
    }

    final text = message.text.toLowerCase();
    if (text.isNotEmpty) {
      for (final keyword in blockedKeywords) {
        if (text.contains(keyword)) {
          return DanmakuFilterDecision.rejected(DanmakuFilterReason.blockedKeyword, keyword: keyword);
        }
      }
    }

    return const DanmakuFilterDecision.allowed();
  }

  static Set<String> _normalizeUsers(Iterable<String> users) =>
      users.map((user) => user.trim().toLowerCase()).where((user) => user.isNotEmpty).toSet();

  static List<String> _normalizeKeywords(Iterable<String> keywords) => keywords
      .map((keyword) => keyword.trim().toLowerCase())
      .where((keyword) => keyword.isNotEmpty)
      .toList(growable: false);
}

/// Why a message was suppressed by [DanmakuFilterPolicy].
enum DanmakuFilterReason {
  /// The sender's display name is on the viewer's block list.
  blockedUser,

  /// The message text contains one of the viewer's blocked keywords.
  blockedKeyword,
}

/// Verdict of [DanmakuFilterPolicy.evaluate].
final class DanmakuFilterDecision {
  /// The message passed the policy and should be shown.
  const DanmakuFilterDecision.allowed() : allowed = true, reason = null, keyword = null;

  /// The message was suppressed for [reason], naming the matched [keyword] when
  /// the reason is [DanmakuFilterReason.blockedKeyword].
  const DanmakuFilterDecision.rejected(DanmakuFilterReason this.reason, {this.keyword}) : allowed = false;

  /// Whether the message passed the policy.
  final bool allowed;

  /// `null` when [allowed] is true.
  final DanmakuFilterReason? reason;

  /// The keyword that matched, when [reason] is [DanmakuFilterReason.blockedKeyword].
  final String? keyword;

  @override
  String toString() => allowed
      ? 'DanmakuFilterDecision.allowed'
      : 'DanmakuFilterDecision.rejected(${reason!.name}${keyword == null ? '' : ': $keyword'})';
}
