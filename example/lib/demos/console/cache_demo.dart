import 'dart:io';
import 'dart:typed_data';

import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart';

/// Two caches, two lifetimes: an in-memory LRU and a disk store.
///
/// The module's value is not "it stores bytes" but the two policies it encodes:
/// eviction (what leaves when the cache is full, and by which rule) and identity
/// (a [CacheKey] is a value object, so two subsystems asking for the same
/// resource get the same entry). The demo also shows the memory module reading
/// the cache's *measured* size, which is one of the few places in the framework
/// where a footprint is a real number rather than a declared estimate.
class CacheDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'cache';

  @override
  ModuleCategory get category => ModuleCategory.foundation;

  @override
  String get nameZh => '缓存：内存 LRU 与磁盘存储';

  @override
  String get nameEn => 'Cache: in-memory LRU and disk storage';

  @override
  String get purposeZh =>
      'MemoryCache 按 maxEntries / maxBytes 淘汰（默认 LRU 策略，可替换），DiskCache 把条目写成 JSON 文件。CacheKey 是值对象，因此"同一个资源"在两层里是同一个键。内存层还会把自己的真实字节数报给 memory 模块。';

  @override
  String get purposeEn =>
      'MemoryCache evicts by maxEntries / maxBytes (LRU by default, replaceable), DiskCache stores entries as JSON files, and CacheKey is a value object so "the same resource" is the same key in both layers. The memory layer also reports its measured byte size to the memory module.';

  @override
  List<String> get pointsZh => const <String>[
    'MemoryCache(maxEntries, maxBytes) — 两层上限，任意一层越界即触发淘汰',
    'eviction 策略可替换：默认 LruCacheEviction，也可实现 CacheEviction 自定规则',
    'CacheEntry.sizeBytes 让内存缓存能上报真实占用（而非估算）',
    'DiskCache(directory) — write / read / entries / remove / clear，条目就是磁盘上的文件',
    'expiresAt 过期条目在读取时被丢弃，不占着位置等清理',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'MemoryCache(maxEntries, maxBytes) — two ceilings; crossing either triggers eviction',
    'The eviction policy is replaceable: LruCacheEviction by default, or your own CacheEviction',
    'CacheEntry.sizeBytes lets the memory cache report a measured footprint instead of an estimate',
    'DiskCache(directory) — write / read / entries / remove / clear, one file per entry',
    'Expired entries are dropped on read rather than waiting for a sweep',
  ];

  @override
  String get snippet => r'''
final memory = MemoryCache<Uint8List>(maxEntries: 3, maxBytes: 512 * 1024);
await memory.write(CacheEntry(key: const CacheKey('room/1'), value: bytes, sizeBytes: bytes.length));

final disk = DiskCache(directory: Directory('${dir}/cache'));
await disk.initialize();
await disk.write(CacheEntry(key: const CacheKey('room/1'), value: bytes, sizeBytes: bytes.length));

print(MediaCoreMemory.report().forModule(MemoryModule.cache)?.bytes);  // measured
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    // ---------------------------------------------------------------- memory
    final memory = MemoryCache<Uint8List>(maxEntries: 3);
    await memory.initialize();

    buffer.writeln('MemoryCache(maxEntries: 3)');

    for (final room in <String>['a', 'b', 'c']) {
      final bytes = Uint8List(1024);
      await memory.write(
        CacheEntry<Uint8List>(
          key: CacheKey('room/$room'),
          value: bytes,
          sizeBytes: bytes.length,
          metadata: <String, Object?>{'room': room},
        ),
      );
      buffer.writeln('  wrote room/$room → ${memory.length} entry(ies), ${memory.sizeBytes} bytes');
    }

    // Reading an entry touches it, which is what makes the next eviction LRU
    // rather than FIFO.
    await memory.read(const CacheKey('room/a'));
    buffer
      ..writeln('  read room/a (touches it, so it is now the most recently used)')
      ..writeln();

    await memory.write(CacheEntry<Uint8List>(key: const CacheKey('room/d'), value: Uint8List(512), sizeBytes: 512));

    final remaining = await memory.entries();
    buffer
      ..writeln('  after writing room/d with 3 entries already held:')
      ..writeln('    retained: ${remaining.map((entry) => entry.key.value).join(', ')}')
      ..writeln('    evicted : room/b — the least recently used, which is what LRU means')
      ..writeln()
      // The memory module sees the real number.
      ..writeln('  the memory account for this cache (measured, not estimated):')
      ..writeln('    ${MediaCoreMemory.report().forModule(MemoryModule.cache)}')
      ..writeln();

    // ---------------------------------------------------------------- expiry
    await memory.write(
      CacheEntry<Uint8List>(
        key: const CacheKey('room/token'),
        value: Uint8List(64),
        sizeBytes: 64,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    );
    final expired = await memory.read(const CacheKey('room/token'));

    buffer
      ..writeln('  a signed-URL entry that expired one second ago: read → $expired')
      ..writeln('    (dropped at read time: a stale URL is worse than a miss)')
      ..writeln();

    // ------------------------------------------------------------------ disk
    final directory = await Directory.systemTemp.createTemp('media_core_cache_demo');
    final disk = DiskCache(directory: directory);
    await disk.initialize();

    for (final room in <String>['a', 'b']) {
      final bytes = Uint8List.fromList(List<int>.generate(256, (index) => index));
      await disk.write(
        CacheEntry<Uint8List>(
          key: CacheKey('room/$room'),
          value: bytes,
          sizeBytes: bytes.length,
          metadata: <String, Object?>{'cachedAt': DateTime.now().toIso8601String()},
        ),
      );
    }

    final files = directory.listSync().whereType<File>().map((file) => file.uri.pathSegments.last).toList()..sort();

    buffer
      ..writeln('DiskCache(directory: ${directory.path})')
      ..writeln('  wrote room/a and room/b → ${files.length} file(s): ${files.join(', ')}')
      ..writeln('  one entry per file, the key percent-encoded into the name — no index to corrupt');

    final reread = await disk.read(const CacheKey('room/a'));
    buffer
      ..writeln(
        '  read room/a after a fresh read from disk: ${reread?.value.length} bytes, '
        'metadata=${reread?.metadata.keys.join(',')}',
      )
      ..writeln('  entries(): ${(await disk.entries()).length}');

    await disk.clear();
    buffer
      ..writeln('  after clear(): ${directory.listSync().whereType<File>().length} file(s) left')
      ..writeln('  remove() is per-key, clear() is per-directory: a host picks the granularity.');

    await directory.delete(recursive: true);
    await memory.dispose();
    await disk.dispose();
    MediaCoreMemory.remove(MemoryModule.cache);

    return buffer.toString();
  }
}
