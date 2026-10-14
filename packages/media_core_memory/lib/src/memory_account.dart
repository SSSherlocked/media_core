import 'package:media_core_memory/src/memory_module.dart';
import 'package:media_core_memory/src/memory_pressure.dart';
import 'package:media_core_memory/src/memory_registry.dart' show MemoryRegistry;

/// Key identifying one contributor inside an account.
///
/// Several instances of the same module report into the same account — a wall's
/// nine cells each hold a danmaku queue, a host may run two kernels — and each
/// needs its own key so the account can sum them instead of keeping whichever
/// reported last.
String memoryContributorKey(Object instance) => '${instance.runtimeType}#${identityHashCode(instance)}';

/// One module's memory ledger.
///
/// Every module that holds memory reports into one of these: how many things it
/// holds ([items]) and what they are assumed to cost ([bytes]). The point is not
/// precision — see `MemoryEstimates` — but attribution: when a device is short
/// on memory, the first question is which part of the framework is holding it,
/// and a single total cannot answer that.
///
/// ## One account, many contributors
///
/// An account is per *module*, and a module can have several live instances. So
/// usage is tracked per contributor key and summed:
///
/// ```dart
/// final _memory = MediaCoreMemory.of(MemoryModule.danmaku);
/// late final String _key = memoryContributorKey(this);
///
/// _memory.report(_key, items: _items.length, bytes: ..., note: 'queue');
/// // ... and on dispose:
/// _memory.withdraw(_key);
/// ```
///
/// The simpler [add]/[remove]/[set] family operates on one implicit contributor,
/// for modules with a single instance (the kernel, the pool) where the ceremony
/// would buy nothing.
///
/// Responsibilities:
///
/// - accumulate and release reported usage, per contributor
/// - track peaks, so a spike is visible after it has passed
/// - enforce an optional per-module ceiling
///
/// It does not:
///
/// - measure real memory (reported values are declared or measured by the
///   module itself)
/// - free anything: releasing is the module's job, this is only the ledger
/// - decide global pressure ([MemoryRegistry] does, from the total)
final class MemoryAccount {
  /// Creates an account for [module].
  MemoryAccount({required this.module, this.limitBytes});

  /// Which consumer this ledger belongs to.
  final MemoryModule module;

  /// Optional ceiling for this module alone, in bytes.
  ///
  /// A module with a tight budget of its own (a thumbnail cache, a danmaku
  /// queue) can enforce it locally instead of waiting for global pressure.
  int? limitBytes;

  /// Key used by the single-instance API.
  static const String implicitContributor = '';

  final Map<String, _Contribution> _contributions = <String, _Contribution>{};

  int _peakBytes = 0;
  int _peakItems = 0;
  int _updates = 0;

  /// Currently reported bytes, summed over contributors.
  int get bytes {
    var total = 0;
    for (final contribution in _contributions.values) {
      total += contribution.bytes;
    }
    return total;
  }

  /// Currently reported item count, summed over contributors.
  int get items {
    var total = 0;
    for (final contribution in _contributions.values) {
      total += contribution.items;
    }
    return total;
  }

  /// How many instances are currently contributing.
  int get contributorCount => _contributions.length;

  /// Highest reported byte total since the last peak reset.
  int get peakBytes => _peakBytes;

  /// Highest reported item count since the last peak reset.
  int get peakItems => _peakItems;

  /// How many updates this account has seen.
  ///
  /// Lets a caller tell "nothing is holding memory" from "nothing ever
  /// reported": an untouched account and an emptied one look the same
  /// otherwise, and they mean different things.
  int get updates => _updates;

  /// Whether this account has ever been reported to.
  bool get hasReported => _updates > 0;

  /// Whether this account currently holds anything.
  bool get isEmpty => bytes == 0 && items == 0;

  /// Whether the module's own ceiling is exceeded.
  bool get isOverLimit {
    final limit = limitBytes;
    return limit != null && limit > 0 && bytes > limit;
  }

  /// Detail from the largest contribution: what the memory actually is.
  String? get note {
    _Contribution? largest;
    for (final contribution in _contributions.values) {
      if (largest == null || contribution.bytes > largest.bytes) {
        largest = contribution;
      }
    }
    return largest?.note;
  }

  /// Sets the detail shown next to the account.
  set note(String? value) {
    _contribution(implicitContributor).note = value;
  }

  /// Reports [key]'s usage, replacing whatever that contributor reported before.
  ///
  /// Replacement rather than accumulation is what makes a per-instance report
  /// idempotent: a module reports what it holds *now*, not a delta, and a
  /// contributor that disappears without withdrawing (a crash inside a
  /// callback) can be overwritten by its own next report instead of adding up
  /// forever.
  void report(String key, {int bytes = 0, int items = 0, String? note}) {
    final contribution = _contribution(key);
    contribution
      ..bytes = bytes < 0 ? 0 : bytes
      ..items = items < 0 ? 0 : items
      ..note = note ?? contribution.note;
    _recordPeaks();
    _updates++;
  }

  /// Drops [key]'s contribution entirely.
  ///
  /// What a module calls when an instance is torn down: its share would
  /// otherwise stay in the total forever, and a growing report that nothing
  /// accounts for is the worst kind of wrong number.
  void withdraw(String key) {
    if (_contributions.remove(key) == null) {
      return;
    }
    _updates++;
  }

  /// Reports additional usage for the implicit contributor.
  ///
  /// Negative values are ignored: a module that means to release calls
  /// [remove], which clamps instead.
  void add({int bytes = 0, int items = 0, String? note}) {
    if (bytes < 0 || items < 0) {
      return;
    }
    final contribution = _contribution(implicitContributor);
    contribution
      ..bytes += bytes
      ..items += items
      ..note = note ?? contribution.note;
    _recordPeaks();
    _updates++;
  }

  /// Releases reported usage for the implicit contributor.
  ///
  /// Clamped at zero: a double release is a bug in the module, and letting it
  /// drive the total negative would corrupt every other module's share.
  void remove({int bytes = 0, int items = 0, String? note}) {
    if (bytes < 0 || items < 0) {
      return;
    }
    final contribution = _contribution(implicitContributor);
    contribution
      ..bytes -= bytes
      ..items -= items
      ..note = note ?? contribution.note;
    if (contribution.bytes < 0) {
      contribution.bytes = 0;
    }
    if (contribution.items < 0) {
      contribution.items = 0;
    }
    _updates++;
  }

  /// Sets the implicit contributor's reported values outright.
  ///
  /// For modules that measured the real number (a download that knows its
  /// partial file size, a recorder that knows how many bytes FFmpeg has
  /// written) rather than counting units.
  void set({int? bytes, int? items, String? note}) {
    final contribution = _contribution(implicitContributor);
    if (bytes != null) {
      contribution.bytes = bytes < 0 ? 0 : bytes;
    }
    if (items != null) {
      contribution.items = items < 0 ? 0 : items;
    }
    contribution.note = note ?? contribution.note;
    _recordPeaks();
    _updates++;
  }

  /// Empties every contributor but keeps the peaks and the update count.
  void clear() {
    _contributions.clear();
    _updates++;
  }

  /// Empties every contributor and forgets the peaks.
  void reset() {
    _contributions.clear();
    _peakBytes = 0;
    _peakItems = 0;
    _updates++;
  }

  /// Forgets the peaks, keeping current values.
  void resetPeaks() {
    _peakBytes = bytes;
    _peakItems = items;
  }

  /// Whether [bytes] fits, both in this module's limit and in [availableBytes].
  ///
  /// [availableBytes] is the registry's remaining budget when the caller has a
  /// registry; `null` skips that half of the check.
  bool canAllocate(int bytes, {int? availableBytes}) {
    if (bytes <= 0) {
      return true;
    }
    final limit = limitBytes;
    if (limit != null && limit > 0 && this.bytes + bytes > limit) {
      return false;
    }
    if (availableBytes != null && bytes > availableBytes) {
      return false;
    }
    return true;
  }

  /// Immutable view of this account.
  MemoryAccountSnapshot snapshot({MemoryPressure pressure = MemoryPressure.normal}) {
    return MemoryAccountSnapshot(
      module: module,
      bytes: bytes,
      items: items,
      peakBytes: _peakBytes,
      peakItems: _peakItems,
      limitBytes: limitBytes,
      note: note,
      pressure: pressure,
      isOverLimit: isOverLimit,
      hasReported: hasReported,
      contributorCount: contributorCount,
    );
  }

  _Contribution _contribution(String key) => _contributions.putIfAbsent(key, _Contribution.new);

  void _recordPeaks() {
    final currentBytes = bytes;
    final currentItems = items;
    if (currentBytes > _peakBytes) {
      _peakBytes = currentBytes;
    }
    if (currentItems > _peakItems) {
      _peakItems = currentItems;
    }
  }

  @override
  String toString() => 'MemoryAccount($module: $bytes bytes, $items items, $contributorCount contributor(s))';
}

final class _Contribution {
  int bytes = 0;
  int items = 0;
  String? note;
}

/// Immutable view of one module's memory ledger.
final class MemoryAccountSnapshot {
  /// Creates an account snapshot.
  const MemoryAccountSnapshot({
    required this.module,
    required this.bytes,
    required this.items,
    this.peakBytes = 0,
    this.peakItems = 0,
    this.limitBytes,
    this.note,
    this.pressure = MemoryPressure.normal,
    this.isOverLimit = false,
    this.hasReported = true,
    this.contributorCount = 0,
  });

  /// Which consumer this ledger belongs to.
  final MemoryModule module;

  /// Reported bytes, summed over contributors.
  final int bytes;

  /// Reported item count, summed over contributors.
  final int items;

  /// Highest byte total seen since the last peak reset.
  final int peakBytes;

  /// Highest item count seen since the last peak reset.
  final int peakItems;

  /// This module's own ceiling, when it has one.
  final int? limitBytes;

  /// Detail about what the items are.
  final String? note;

  /// Global pressure at the time of the report.
  final MemoryPressure pressure;

  /// Whether this module is over its own ceiling.
  final bool isOverLimit;

  /// Whether the account has ever been reported to.
  final bool hasReported;

  /// How many instances contributed.
  final int contributorCount;

  /// Whether this account currently holds anything.
  bool get isEmpty => bytes == 0 && items == 0;

  @override
  String toString() {
    final detail = note == null ? '' : ' ($note)';
    final instances = contributorCount > 1 ? ' from $contributorCount instances' : '';
    return 'MemoryAccountSnapshot($module: $bytes bytes, $items items$instances$detail)';
  }
}
