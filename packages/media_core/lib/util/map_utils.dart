/// Map related utilities.
abstract final class MapUtils {
  MapUtils._();

  /// Returns empty map when value is null.
  static Map<K, V> emptyIfNull<K, V>(Map<K, V>? value) {
    return value ?? <K, V>{};
  }

  /// Checks whether map is empty.
  static bool isEmpty<K, V>(Map<K, V>? value) {
    return value == null || value.isEmpty;
  }

  /// Checks whether map is not empty.
  static bool isNotEmpty<K, V>(Map<K, V>? value) {
    return !isEmpty(value);
  }

  /// Returns value or null.
  static V? get<K, V>(Map<K, V> map, K key) {
    return map[key];
  }

  /// Returns value or fallback.
  static V valueOr<K, V>(Map<K, V> map, K key, V fallback) {
    return map[key] ?? fallback;
  }

  /// Checks whether map contains key.
  static bool hasKey<K, V>(Map<K, V> map, K key) {
    return map.containsKey(key);
  }

  /// Checks whether map contains value.
  static bool hasValue<K, V>(Map<K, V> map, V value) {
    return map.containsValue(value);
  }

  /// Creates a copy of map.
  static Map<K, V> copy<K, V>(Map<K, V> map) {
    return Map<K, V>.from(map);
  }

  /// Merges two maps.
  static Map<K, V> merge<K, V>(Map<K, V> first, Map<K, V> second) {
    return {...first, ...second};
  }

  /// Merges multiple maps.
  static Map<K, V> mergeAll<K, V>(Iterable<Map<K, V>> maps) {
    final result = <K, V>{};

    maps.forEach(result.addAll);

    return result;
  }

  /// Removes null values.
  static Map<K, V> whereNotNull<K, V>(Map<K, V?> map) {
    return map.entries
        .where((entry) => entry.value != null)
        .map((entry) => MapEntry<K, V>(entry.key, entry.value as V))
        .fold(<K, V>{}, (result, entry) {
          result[entry.key] = entry.value;
          return result;
        });
  }

  /// Filters map entries.
  static Map<K, V> where<K, V>(Map<K, V> map, bool Function(K key, V value) test) {
    return Map<K, V>.fromEntries(map.entries.where((entry) => test(entry.key, entry.value)));
  }

  /// Maps keys.
  static Map<R, V> mapKeys<K, V, R>(Map<K, V> map, R Function(K key) transform) {
    return map.map((key, value) {
      return MapEntry(transform(key), value);
    });
  }

  /// Maps values.
  static Map<K, R> mapValues<K, V, R>(Map<K, V> map, R Function(V value) transform) {
    return map.map((key, value) {
      return MapEntry(key, transform(value));
    });
  }

  /// Converts map keys to strings.
  static Map<String, V> stringifyKeys<V>(Map<Object, V> map) {
    return map.map((key, value) {
      return MapEntry(key.toString(), value);
    });
  }

  /// Gets nested map value.
  static dynamic path(Map<String, dynamic> map, List<String> keys) {
    dynamic current = map;

    for (final key in keys) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }

    return current;
  }

  /// Converts map into query parameters.
  static String queryString(Map<String, dynamic> map) {
    return map.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
  }

  /// Checks map equality.
  static bool equals<K, V>(Map<K, V> first, Map<K, V> second) {
    if (identical(first, second)) {
      return true;
    }

    if (first.length != second.length) {
      return false;
    }

    for (final key in first.keys) {
      if (!second.containsKey(key)) {
        return false;
      }

      if (first[key] != second[key]) {
        return false;
      }
    }

    return true;
  }

  /// Converts iterable pairs into map.
  static Map<K, V> fromPairs<K, V>(Iterable<(K, V)> pairs) {
    return {for (final pair in pairs) pair.$1: pair.$2};
  }
}
