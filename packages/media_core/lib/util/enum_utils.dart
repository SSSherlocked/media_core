import 'dart:math';

/// General-purpose enum utilities.
abstract final class EnumUtils {
  EnumUtils._();

  /// Returns the enum name without its type prefix.
  ///
  /// Example:
  /// `EnumUtils.name(MyEnum.value)` -> `value`
  static String name<T extends Enum>(T value) {
    final raw = value.toString();
    final separatorIndex = raw.indexOf('.');

    if (separatorIndex == -1) {
      return raw;
    }

    return raw.substring(separatorIndex + 1);
  }

  /// Returns the enum name in lowercase.
  static String lowerName<T extends Enum>(T value) {
    return name(value).toLowerCase();
  }

  /// Returns the enum name in uppercase.
  static String upperName<T extends Enum>(T value) {
    return name(value).toUpperCase();
  }

  /// Finds an enum value by its name.
  ///
  /// Returns `null` when no matching value exists.
  static T? byName<T extends Enum>(Iterable<T> values, String value) {
    for (final item in values) {
      if (name(item) == value) {
        return item;
      }
    }

    return null;
  }

  /// Finds an enum value by its name, ignoring case.
  static T? byNameIgnoreCase<T extends Enum>(Iterable<T> values, String value) {
    final normalized = value.toLowerCase();

    for (final item in values) {
      if (name(item).toLowerCase() == normalized) {
        return item;
      }
    }

    return null;
  }

  /// Finds an enum value by its name after trimming whitespace.
  static T? byNameTrimmed<T extends Enum>(Iterable<T> values, String value) {
    final normalized = value.trim();

    for (final item in values) {
      if (name(item) == normalized) {
        return item;
      }
    }

    return null;
  }

  /// Finds an enum value by its name, ignoring case and whitespace.
  static T? byNameFlexible<T extends Enum>(Iterable<T> values, String value) {
    final normalized = value.trim().toLowerCase();

    for (final item in values) {
      if (name(item).toLowerCase() == normalized) {
        return item;
      }
    }

    return null;
  }

  /// Returns the enum value at [index], or `null` when out of range.
  static T? byIndex<T extends Enum>(Iterable<T> values, int index) {
    if (index < 0) {
      return null;
    }

    for (final value in values) {
      if (value.index == index) {
        return value;
      }
    }

    return null;
  }

  /// Returns the enum value at [index], or [fallback] when unavailable.
  static T byIndexOr<T extends Enum>(Iterable<T> values, int index, T fallback) {
    return byIndex(values, index) ?? fallback;
  }

  /// Returns the enum value at [index], or throws [RangeError].
  static T requireByIndex<T extends Enum>(Iterable<T> values, int index) {
    final value = byIndex(values, index);

    if (value != null) {
      return value;
    }

    throw RangeError.index(index, values, 'index');
  }

  /// Returns the first enum value matching [test].
  static T? firstWhere<T extends Enum>(Iterable<T> values, bool Function(T value) test) {
    for (final value in values) {
      if (test(value)) {
        return value;
      }
    }

    return null;
  }

  /// Returns whether any enum value matches [test].
  static bool any<T extends Enum>(Iterable<T> values, bool Function(T value) test) {
    for (final value in values) {
      if (test(value)) {
        return true;
      }
    }

    return false;
  }

  /// Returns whether every enum value matches [test].
  static bool every<T extends Enum>(Iterable<T> values, bool Function(T value) test) {
    for (final value in values) {
      if (!test(value)) {
        return false;
      }
    }

    return true;
  }

  /// Converts enum values to their names.
  static List<String> names<T extends Enum>(Iterable<T> values) {
    return [for (final value in values) name(value)];
  }

  /// Converts enum values to a map keyed by their names.
  static Map<String, T> byNames<T extends Enum>(Iterable<T> values) {
    final result = <String, T>{};

    for (final value in values) {
      result[name(value)] = value;
    }

    return result;
  }

  /// Returns the index of [value].
  static int index<T extends Enum>(T value) {
    return value.index;
  }

  /// Returns whether [value] is the first enum value.
  static bool isFirst<T extends Enum>(T value) {
    return value.index == 0;
  }

  /// Returns whether [value] is the last enum value.
  ///
  /// Performance optimized: avoids creating unnecessary lists.
  static bool isLast<T extends Enum>(T value, Iterable<T> values) {
    if (values.isEmpty) {
      return false;
    }

    // Use last directly without converting to list
    return identical(values.last, value);
  }

  /// Returns the next enum value, wrapping to the first value.
  ///
  /// Performance optimized: caches the list for sequential access.
  static T? next<T extends Enum>(Iterable<T> values, T current, {bool wrap = true}) {
    // Early return for empty iterable
    if (values.isEmpty) {
      return null;
    }

    // Convert to list once for index-based access
    final list = values.toList(growable: false);
    final index = list.indexOf(current);

    // Return null if current value is not in the list
    if (index == -1) {
      return null;
    }

    final nextIndex = index + 1;

    // Return next value if available
    if (nextIndex < list.length) {
      return list[nextIndex];
    }

    // Wrap to first value if enabled, otherwise return null
    return wrap ? list.first : null;
  }

  /// Returns the previous enum value, wrapping to the last value.
  ///
  /// Performance optimized: caches the list for sequential access.
  static T? previous<T extends Enum>(Iterable<T> values, T current, {bool wrap = true}) {
    // Early return for empty iterable
    if (values.isEmpty) {
      return null;
    }

    // Convert to list once for index-based access
    final list = values.toList(growable: false);
    final index = list.indexOf(current);

    // Return null if current value is not in the list
    if (index == -1) {
      return null;
    }

    final previousIndex = index - 1;

    // Return previous value if available
    if (previousIndex >= 0) {
      return list[previousIndex];
    }

    // Wrap to last value if enabled, otherwise return null
    return wrap ? list.last : null;
  }

  /// Returns a map from enum values to their names.
  static Map<T, String> toNameMap<T extends Enum>(Iterable<T> values) {
    final result = <T, String>{};

    for (final value in values) {
      result[value] = name(value);
    }

    return result;
  }

  /// Returns a map from enum values to their indices.
  static Map<T, int> toIndexMap<T extends Enum>(Iterable<T> values) {
    final result = <T, int>{};

    for (final value in values) {
      result[value] = value.index;
    }

    return result;
  }

  /// Safely parses a string to an enum value, returning [defaultValue] if parsing fails.
  ///
  /// Example:
  /// `EnumUtils.parseOrDefault(Status.values, 'active', Status.pending)`
  static T parseOrDefault<T extends Enum>(Iterable<T> values, String? input, T defaultValue) {
    if (input == null || input.isEmpty) {
      return defaultValue;
    }

    return byNameFlexible(values, input) ?? defaultValue;
  }

  /// Returns a random enum value from the provided values.
  ///
  /// Uses [random] if provided, otherwise uses a default [Random] instance.
  static T random<T extends Enum>(Iterable<T> values, [Random? random]) {
    if (values.isEmpty) {
      throw StateError('Cannot get random value from empty enum values');
    }

    final list = values.toList(growable: false);
    final rng = random ?? Random();
    return list[rng.nextInt(list.length)];
  }

  /// Returns a list of all enum values that match the predicate [test].
  static List<T> where<T extends Enum>(Iterable<T> values, bool Function(T value) test) {
    final result = <T>[];

    for (final value in values) {
      if (test(value)) {
        result.add(value);
      }
    }

    return result;
  }

  /// Returns a set of all enum values.
  static Set<T> toSet<T extends Enum>(Iterable<T> values) {
    return values.toSet();
  }

  /// Checks if [value] is contained in the provided [values].
  static bool contains<T extends Enum>(Iterable<T> values, T value) {
    return values.contains(value);
  }

  /// Returns the enum value if it exists, otherwise returns `null`.
  ///
  /// This is a safe alias for [byNameFlexible].
  static T? tryParse<T extends Enum>(Iterable<T> values, String? input) {
    if (input == null || input.isEmpty) {
      return null;
    }
    return byNameFlexible(values, input);
  }

  /// Returns the enum value if it exists, otherwise throws [ArgumentError].
  static T requireByName<T extends Enum>(Iterable<T> values, String input) {
    final result = byName(values, input);
    if (result != null) {
      return result;
    }
    throw ArgumentError.value(input, 'input', 'No enum value found with name: $input');
  }

  /// Gets all enum names as a set (unique values).
  static Set<String> namesSet<T extends Enum>(Iterable<T> values) {
    return names(values).toSet();
  }

  /// Returns a map from enum indices to their values.
  static Map<int, T> byIndices<T extends Enum>(Iterable<T> values) {
    final result = <int, T>{};

    for (final value in values) {
      result[value.index] = value;
    }

    return result;
  }

  /// Returns the difference between two enum value collections.
  ///
  /// Returns values that are in [values1] but not in [values2].
  static List<T> difference<T extends Enum>(Iterable<T> values1, Iterable<T> values2) {
    final set2 = values2.toSet();
    final result = <T>[];

    for (final value in values1) {
      if (!set2.contains(value)) {
        result.add(value);
      }
    }

    return result;
  }

  /// Returns the intersection of two enum value collections.
  ///
  /// Returns values that are in both [values1] and [values2].
  static List<T> intersection<T extends Enum>(Iterable<T> values1, Iterable<T> values2) {
    final set2 = values2.toSet();
    final result = <T>[];

    for (final value in values1) {
      if (set2.contains(value)) {
        result.add(value);
      }
    }

    return result;
  }

  /// Returns the union of two enum value collections (no duplicates).
  static List<T> union<T extends Enum>(Iterable<T> values1, Iterable<T> values2) {
    final result = <T>[];

    // Add all values from first collection
    for (final value in values1) {
      if (!result.contains(value)) {
        result.add(value);
      }
    }

    // Add values from second collection that are not already present
    for (final value in values2) {
      if (!result.contains(value)) {
        result.add(value);
      }
    }

    return result;
  }

  /// Checks if [values] are sorted by their index order.
  static bool isSorted<T extends Enum>(Iterable<T> values) {
    int? previousIndex;

    for (final value in values) {
      if (previousIndex != null && value.index <= previousIndex) {
        return false;
      }
      previousIndex = value.index;
    }

    return true;
  }

  /// Sorts enum values by their index order.
  static List<T> sort<T extends Enum>(Iterable<T> values) {
    return values.toList(growable: false)..sort((a, b) => a.index.compareTo(b.index));
  }

  /// Returns a map of enum values grouped by some property.
  static Map<K, List<T>> groupBy<T extends Enum, K>(Iterable<T> values, K Function(T value) keySelector) {
    final result = <K, List<T>>{};

    for (final value in values) {
      final key = keySelector(value);
      result.putIfAbsent(key, () => []).add(value);
    }

    return result;
  }

  /// Returns the enum value with the minimum index.
  static T? min<T extends Enum>(Iterable<T> values) {
    if (values.isEmpty) {
      return null;
    }

    T? minValue;
    int? minIndex;

    for (final value in values) {
      if (minIndex == null || value.index < minIndex) {
        minValue = value;
        minIndex = value.index;
      }
    }

    return minValue;
  }

  /// Returns the enum value with the maximum index.
  static T? max<T extends Enum>(Iterable<T> values) {
    if (values.isEmpty) {
      return null;
    }

    T? maxValue;
    int? maxIndex;

    for (final value in values) {
      if (maxIndex == null || value.index > maxIndex) {
        maxValue = value;
        maxIndex = value.index;
      }
    }

    return maxValue;
  }

  /// Returns the difference between two enum values' indices.
  static int indexDifference<T extends Enum>(T value1, T value2) {
    return (value1.index - value2.index).abs();
  }

  /// Returns whether two enum values are adjacent (index difference of 1).
  static bool areAdjacent<T extends Enum>(T value1, T value2) {
    return indexDifference(value1, value2) == 1;
  }

  /// Returns an enum value by its ordinal (index) with type safety.
  ///
  /// Unlike [byIndex], this requires the values list to be provided as a list
  /// for direct index access, which is more efficient for known lists.
  static T? byOrdinal<T extends Enum>(List<T> values, int ordinal) {
    if (ordinal < 0 || ordinal >= values.length) {
      return null;
    }
    return values[ordinal];
  }

  /// Returns an enum value by its ordinal, or throws [RangeError].
  static T requireByOrdinal<T extends Enum>(List<T> values, int ordinal) {
    if (ordinal < 0 || ordinal >= values.length) {
      throw RangeError.range(ordinal, 0, values.length - 1, 'ordinal');
    }
    return values[ordinal];
  }

  /// Converts a list of enum values to a comma-separated string of names.
  static String joinNames<T extends Enum>(
    Iterable<T> values, {
    String separator = ', ',
    String Function(T value)? formatter,
  }) {
    final formattedNames = values.map((value) {
      final nameValue = name(value);
      return formatter != null ? formatter(value) : nameValue;
    });
    return formattedNames.join(separator);
  }

  /// Checks if an enum value's name matches a pattern.
  static bool nameMatches<T extends Enum>(T value, String pattern, {bool caseSensitive = true}) {
    final valueName = name(value);
    if (caseSensitive) {
      return valueName.contains(pattern);
    }
    return valueName.toLowerCase().contains(pattern.toLowerCase());
  }

  /// Returns a list of enum values whose names contain the pattern.
  static List<T> whereNameContains<T extends Enum>(Iterable<T> values, String pattern, {bool caseSensitive = true}) {
    final result = <T>[];
    for (final value in values) {
      if (nameMatches(value, pattern, caseSensitive: caseSensitive)) {
        result.add(value);
      }
    }
    return result;
  }
}
