import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_core/cache/cache_entry.dart';
import 'package:media_core/cache/cache_key.dart';
import 'package:media_core/cache/cache_storage.dart';

/// Disk-backed cache storage for byte-oriented cache values.
///
/// [DiskCache] stores one cache entry per file.
///
/// The cache format is intentionally simple:
///
/// ```text
/// <cache directory>/
///   <encoded key>.json
/// ```
///
/// The entry value is stored as Base64 when written to disk.
///
/// This class is intended for byte-oriented data such as media metadata,
/// manifests, thumbnails, small network responses, and other cacheable
/// payloads.
///
/// Large media payloads should generally use a dedicated streaming/file cache
/// rather than loading the entire value into memory.
final class DiskCache implements CacheStorage<Uint8List> {
  /// Creates disk storage rooted at [directory].
  DiskCache({required this.directory});

  /// Directory holding one encoded-key `.json` file per entry.
  final Directory directory;

  bool _initialized = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();

    if (!_initialized) {
      await directory.create(recursive: true);
      _initialized = true;
    }
  }

  @override
  Future<CacheEntry<Uint8List>?> read(CacheKey key) async {
    _ensureReady();

    final file = _fileFor(key);

    if (!file.existsSync()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final Object? decoded = jsonDecode(content);

      if (decoded is! Map) {
        await file.delete();
        return null;
      }

      final map = Map<String, dynamic>.from(decoded);

      final createdAtValue = map['createdAt'] as String?;
      final accessedAtValue = map['accessedAt'] as String?;
      final expiresAtValue = map['expiresAt'] as String?;

      final createdAt = createdAtValue == null ? null : DateTime.tryParse(createdAtValue);

      final accessedAt = accessedAtValue == null ? null : DateTime.tryParse(accessedAtValue);

      final expiresAt = expiresAtValue == null ? null : DateTime.tryParse(expiresAtValue);

      final Object? value = map['value'];

      if (createdAt == null || accessedAt == null || value is! String) {
        await file.delete();
        return null;
      }

      final bytes = Uint8List.fromList(base64Decode(value));

      final Object? metadataValue = map['metadata'];

      final metadata = metadataValue is Map ? Map<String, Object?>.from(metadataValue) : const <String, Object?>{};

      final entry = CacheEntry<Uint8List>(
        key: key,
        value: bytes,
        createdAt: createdAt,
        accessedAt: accessedAt,
        expiresAt: expiresAt,
        sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? bytes.length,
        metadata: metadata,
      );

      if (entry.isExpired) {
        await file.delete();
        return entry;
      }

      final touched = entry.touch();
      await _writeEntry(touched);

      return touched;
    } on FormatException {
      if (file.existsSync()) {
        await file.delete();
      }

      return null;
    }
  }

  @override
  Future<void> write(CacheEntry<Uint8List> entry) async {
    _ensureReady();

    await _writeEntry(entry);
  }

  @override
  Future<bool> remove(CacheKey key) async {
    _ensureReady();

    final file = _fileFor(key);

    if (!file.existsSync()) {
      return false;
    }

    await file.delete();
    return true;
  }

  @override
  Future<void> clear() async {
    _ensureReady();

    if (!directory.existsSync()) {
      return;
    }

    await for (final FileSystemEntity entity in directory.list(followLinks: false)) {
      if (entity is File) {
        await entity.delete();
      }
    }
  }

  @override
  Future<bool> contains(CacheKey key) async {
    _ensureReady();

    final file = _fileFor(key);

    if (!file.existsSync()) {
      return false;
    }

    final entry = await read(key);

    return entry != null;
  }

  @override
  Future<List<CacheEntry<Uint8List>>> entries() async {
    _ensureReady();

    if (!directory.existsSync()) {
      return const <CacheEntry<Uint8List>>[];
    }

    final result = <CacheEntry<Uint8List>>[];

    await for (final FileSystemEntity entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }

      final fileName = entity.uri.pathSegments.last;
      final encodedKey = fileName.substring(0, fileName.length - '.json'.length);

      final keyValue = Uri.decodeComponent(encodedKey);

      final entry = await read(CacheKey(keyValue));

      if (entry != null) {
        result.add(entry);
      }
    }

    return List<CacheEntry<Uint8List>>.unmodifiable(result);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
  }

  File _fileFor(CacheKey key) {
    final encoded = Uri.encodeComponent(key.value);

    return File('${directory.path}${Platform.pathSeparator}$encoded.json');
  }

  Future<void> _writeEntry(CacheEntry<Uint8List> entry) async {
    final file = _fileFor(entry.key);

    final map = <String, dynamic>{
      'key': entry.key.value,
      'value': base64Encode(entry.value),
      'createdAt': entry.createdAt.toIso8601String(),
      'accessedAt': entry.accessedAt.toIso8601String(),
      'expiresAt': entry.expiresAt?.toIso8601String(),
      'sizeBytes': entry.sizeBytes,
      'metadata': entry.metadata,
    };

    await file.writeAsString(jsonEncode(map), flush: true);
  }

  void _ensureReady() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('DiskCache has not been initialized.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DiskCache has been disposed.');
    }
  }
}
