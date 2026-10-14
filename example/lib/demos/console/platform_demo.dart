import 'dart:io';

import 'package:example/demos/module_demo.dart';
import 'package:media_core_audio/media_core_audio.dart';

/// Permissions and the ffmpeg download arguments.
///
/// Two things a developer integrating this module has to get right on the
/// platform side, shown without side effects: what the permission layer answers
/// (it never pops a dialog here — `request` is what a host calls), and exactly
/// which ffmpeg arguments a download turns into.
class PlatformDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'platform';

  @override
  ModuleCategory get category => ModuleCategory.capability;

  @override
  String get nameZh => '权限与下载参数';

  @override
  String get nameEn => 'Permissions & download arguments';

  @override
  String get purposeZh =>
      'AudioPermissionService 把"要做什么"映射成平台权限（通知 / 媒体库 / 悬浮窗），平台没有该权限时返回 true；MusicDownloader.buildArguments 是纯函数，下载前可以直接看 ffmpeg 会收到什么。';

  @override
  String get purposeEn =>
      'AudioPermissionService maps "what am I doing" to a platform permission (notifications / media library / overlay) and answers true where the platform has none; MusicDownloader.buildArguments is pure, so the exact ffmpeg call is inspectable before a download runs.';

  @override
  List<String> get pointsZh => const <String>[
    'isGranted 只读状态，request 才会弹窗 / 拉起设置页',
    '悬浮窗权限没有对话框：request 会等用户在系统设置页开关后才返回',
    'requestAll 遇到拒绝即停止，不连弹多个对话框',
    'buildArguments：copy 只用于可命名的容器，流式 URL 转码；-xerror 让损坏的下载失败而不是留半成品',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'isGranted only reads state; request is what shows UI',
    'The overlay permission has no dialog: request waits for the system settings switch',
    'requestAll stops at the first refusal instead of stacking dialogs',
    'buildArguments: copy only for a nameable container, streams are transcoded; -xerror fails a corrupt download instead of leaving a partial file',
  ];

  @override
  String get snippet => '''
final permissions = AudioPermissionService();

await permissions.isGranted(AudioPermission.notifications);   // read only
await permissions.request(AudioPermission.desktopLyricOverlay); // may open settings

final downloader = MusicDownloader();
final args = downloader.buildArguments(request);   // pure, printable
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();
    final permissions = AudioPermissionService();

    buffer
      ..writeln('platform: ${Platform.operatingSystem}')
      ..writeln('permissions (read-only; no dialog is shown here):');

    for (final permission in AudioPermission.values) {
      buffer.writeln('  ${permission.name.padRight(20)} granted=${await permissions.isGranted(permission)}');
    }

    buffer
      ..writeln()
      ..writeln('  desktop platforms answer true: they have no such permission to ask for,')
      ..writeln('  so a host can call these unconditionally.')
      ..writeln();

    final downloader = MusicDownloader();

    final mp3 = MusicDownloadRequest(
      url: 'https://cdn.example.com/live/stream.m3u8?token=abc',
      outputPath: '${Directory.systemTemp.path}${Platform.pathSeparator}demo_song.mp3',
      headers: const <String, String>{'Referer': 'https://example.com'},
      userAgent: 'media_core-demo/1.0',
      format: MusicDownloadFormat.mp3,
      expectedDuration: const Duration(minutes: 3),
      title: 'Demo Song',
      artist: 'Artist A',
      album: 'Demo Album',
    );

    buffer
      ..writeln('ffmpeg arguments — streaming URL → MP3 320k:')
      ..writeln(_indent(downloader.buildArguments(mp3)))
      ..writeln();

    // A resolved file-like URL keeps its own container: no re-encode, no
    // quality loss, which is the whole point of the copy branch.
    final copy = MusicDownloadRequest.forTrack(
      track: const MusicTrack(id: 'flac_1', title: 'Lossless Song', artist: 'Artist A', sourceId: 'demo'),
      source: TrackSource(uri: Uri.parse('https://cdn.example.com/lossless.flac')),
      directory: Directory.systemTemp.path,
    );

    buffer
      ..writeln(
        'plan for a .flac URL: format=${copy.format.name} → ${copy.outputPath.split(Platform.pathSeparator).last}',
      )
      ..writeln('(copy branch: bytes are copied, extension preserved)')
      ..writeln()
      ..writeln('ffmpeg arguments — copy branch:')
      ..writeln(_indent(downloader.buildArguments(copy)));

    await downloader.dispose();

    return buffer.toString();
  }

  String _indent(List<String> arguments) {
    return arguments.map((argument) => '  $argument').join('\n');
  }
}
