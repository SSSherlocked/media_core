import 'package:media_core_logging/src/log_category.dart';
import 'package:media_core_logging/src/player_logger.dart';

/// Decides whether a record reaches the sinks.
///
/// Level and per-category levels live on the logger because every call goes
/// through them; this adds the filtering a *developer* wants while looking at
/// output: narrow to one module, search for a string, and stop one hot path from
/// burying everything else.
final class LogFilter {
  /// Creates a filter limited to [categories] (all when null) and [keyword].
  LogFilter({Set<LogCategory>? categories, this.keyword})
    : _categories = categories == null ? null : Set<LogCategory>.unmodifiable(categories);

  /// Creates a filter that accepts everything.
  factory LogFilter.none() => LogFilter();

  /// When non-empty, only these categories pass.
  final Set<LogCategory>? _categories;

  /// When non-empty, only messages containing it (case-insensitively) pass.
  final String? keyword;

  /// Categories this filter allows, or `null` for all.
  Set<LogCategory>? get categories => _categories == null ? null : Set<LogCategory>.unmodifiable(_categories);

  /// Whether [record] passes.
  bool accepts(PlayerLogRecord record) {
    final categories = _categories;
    if (categories != null && categories.isNotEmpty && !categories.contains(record.category)) {
      return false;
    }

    final needle = keyword?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      final haystack = '${record.message} ${record.fields}'.toLowerCase();
      if (!haystack.contains(needle)) {
        return false;
      }
    }

    return true;
  }

  /// The same filter with [categories] added.
  LogFilter withCategories(Iterable<LogCategory> categories) =>
      LogFilter(categories: {...?_categories, ...categories}, keyword: keyword);

  /// The same filter with a keyword.
  LogFilter withKeyword(String? keyword) => LogFilter(categories: _categories, keyword: keyword);
}

/// Counts and drops records that arrive too often.
///
/// For hot paths: a per-frame log is useful for ten seconds and a flood
/// afterwards, and a flood is what makes the log useless exactly when something
/// is going wrong. Dropped records are counted, and the count is attached to the
/// next record that is allowed through, so a reader can tell "this happened
/// once" from "this happened four thousand times".
final class LogThrottle {
  /// Creates a throttle allowing [maxRecords] per [window].
  LogThrottle({this.maxRecords = 20, this.window = const Duration(seconds: 1)});

  /// How many records per [window] are allowed through.
  final int maxRecords;

  /// Window length.
  final Duration window;

  final Map<LogCategory, List<DateTime>> _history = <LogCategory, List<DateTime>>{};
  final Map<LogCategory, int> _suppressed = <LogCategory, int>{};

  /// Whether [category] may emit at [now], and how many were dropped since it
  /// last did.
  ({bool allowed, int suppressed}) admit(LogCategory category, DateTime now) {
    final history = _history.putIfAbsent(category, () => <DateTime>[])
      ..removeWhere((stamp) => now.difference(stamp) > window);

    if (history.length >= maxRecords) {
      _suppressed[category] = (_suppressed[category] ?? 0) + 1;
      return (allowed: false, suppressed: 0);
    }

    history.add(now);
    final suppressed = _suppressed.remove(category) ?? 0;
    return (allowed: true, suppressed: suppressed);
  }

  /// Forgets every window and count.
  void reset() {
    _history.clear();
    _suppressed.clear();
  }
}
