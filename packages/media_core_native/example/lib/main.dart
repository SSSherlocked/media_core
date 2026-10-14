import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_native/media_core_native.dart';

/// Shows what the platform probe answers on this device.
///
/// This is the package's own debugging surface: the native side can only be
/// judged on a real device, and this screen prints exactly what crossed the
/// channel — before any engine has an opinion about it.
void main() {
  runApp(const ProbeApp());
}

/// The example's root widget.
class ProbeApp extends StatelessWidget {
  /// Creates the probe example app.
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'media_core_native', home: ProbePage());
  }
}

/// Page that runs the platform probe and prints what it answered.
class ProbePage extends StatefulWidget {
  /// Creates the probe page.
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  NativePlatformProvider? _provider;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    unawaited(_probe());
  }

  Future<void> _probe() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider = await NativePlatformProvider.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _provider = provider;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform probe'),
        actions: <Widget>[
          IconButton(tooltip: 'Probe again', onPressed: _loading ? null : _probe, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (_error != null) _Section(title: 'Failure', rows: <String, Object?>{'error': '$_error'}),
                if (provider != null) ...<Widget>[
                  _Section(
                    title: 'Reported',
                    rows: <String, Object?>{
                      'provider ready': provider.isReady,
                      'capabilities reported': provider.capabilities.reported,
                      'device reported': provider.device.reported,
                      'codecs reported': provider.codecs.reported,
                    },
                  ),
                  _Section(
                    title: 'Platform',
                    rows: <String, Object?>{
                      'type': provider.type.value,
                      'name': provider.info.name,
                      'version': provider.info.version,
                      'build': provider.info.buildNumber,
                      'architecture': provider.info.architecture,
                      'model': provider.info.deviceModel,
                      'emulator': provider.info.isEmulator,
                    },
                  ),
                  _Section(
                    title: 'Capabilities',
                    rows: <String, Object?>{
                      'hardware decode': provider.capabilities.hardwareDecode,
                      'software decode': provider.capabilities.softwareDecode,
                      'picture in picture': provider.capabilities.pictureInPicture,
                      'background playback': provider.capabilities.backgroundPlayback,
                      'external display': provider.capabilities.externalDisplay,
                      'fullscreen': provider.capabilities.fullscreen,
                    },
                  ),
                  _Section(
                    title: 'Device',
                    rows: <String, Object?>{
                      'cpu cores': provider.device.cpuCores,
                      'total ram (MB)': provider.device.totalRamMb,
                      'low ram device': provider.device.lowRamDevice,
                      '64-bit ABI': provider.device.supports64BitAbi,
                      'low end (derived)': provider.device.isLowEnd,
                      'software decode threads': provider.device.softwareDecodeThreads,
                    },
                  ),
                  _Section(
                    title: 'Video codecs',
                    rows: <String, Object?>{
                      for (final codec in VideoCodec.values)
                        codec.name: switch (provider.codecs[codec]) {
                          null => 'not reported',
                          final support when !support.hardware => 'software only',
                          final support =>
                            'hardware'
                                '${support.hasSizeLimits ? ' up to ${support.maxWidth}x${support.maxHeight}' : ''}',
                        },
                    },
                    footer: 'A codec that is absent answers "unknown", not "unsupported".',
                  ),
                  _Section(
                    title: 'Questions a backend asks',
                    rows: <String, Object?>{
                      'H.264 @1080p': provider.canHardwareDecode(VideoCodec.h264, width: 1920, height: 1080),
                      'HEVC @1080p': provider.canHardwareDecode(VideoCodec.hevc, width: 1920, height: 1080),
                      'HEVC @4K': provider.canHardwareDecode(VideoCodec.hevc, width: 3840, height: 2160),
                      'AV1 @1080p': provider.canHardwareDecode(VideoCodec.av1, width: 1920, height: 1080),
                    },
                    footer: 'null means the platform has no answer; a backend then lets the engine try.',
                  ),
                ],
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.footer});

  final String title;
  final Map<String, Object?> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 3, child: Text(entry.key, style: theme.textTheme.bodyMedium)),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${entry.value}',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (footer != null) ...<Widget>[const SizedBox(height: 6), Text(footer!, style: theme.textTheme.bodySmall)],
          ],
        ),
      ),
    );
  }
}
