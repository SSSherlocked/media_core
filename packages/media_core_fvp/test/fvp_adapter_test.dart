import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart' show Alignment, BoxFit, Color, FilterQuality;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_fvp/media_core_fvp.dart';

void main() {
  group('FvpPlayerAdapter.encodeHeaders', () {
    test('each accepted header becomes one CRLF-terminated line', () {
      final encoded = FvpPlayerAdapter.encodeHeaders(const <String, String>{
        'User-Agent': 'media_core/1.0',
        'Referer': 'https://example.com',
      });

      expect(encoded, 'User-Agent: media_core/1.0\r\nReferer: https://example.com\r\n');
    });

    test('an empty map encodes to an empty string', () {
      expect(FvpPlayerAdapter.encodeHeaders(const <String, String>{}), isEmpty);
    });

    test('header-injecting lines are dropped, not escaped', () {
      // avio.headers parses CRLF lines; a value carrying CR/LF would become a
      // second header line, so the safe answer is to refuse the pair.
      final encoded = FvpPlayerAdapter.encodeHeaders(const <String, String>{
        'Good': 'ok',
        'Bad\rName': 'x',
        'Bad:Name': 'x',
        '': 'value',
        'Splitting': 'one\r\nInjected: two',
      });

      expect(encoded, 'Good: ok\r\n');
      expect(encoded, isNot(contains('Injected')));
    });
  });

  group('FvpPlayerAdapter.defaultCapabilities', () {
    test('what libmdk genuinely answers stays on', () {
      const caps = FvpPlayerAdapter.defaultCapabilities;

      expect(caps.supportsLive, isTrue);
      expect(caps.supportsSeek, isTrue);
      expect(caps.supportsPause, isTrue);
      expect(caps.supportsStop, isTrue);
      expect(caps.supportsRateControl, isTrue);
      expect(caps.supportsVolumeControl, isTrue);
      expect(caps.supportsEngineOptions, isTrue);
      expect(caps.supportsVideoSizeChanged, isTrue);
    });

    test('the signals libmdk cannot produce stay off', () {
      const caps = FvpPlayerAdapter.defaultCapabilities;

      // No decoded-frame callback: claiming it would arm a watchdog that can
      // never be fed and tear down healthy streams.
      expect(caps.supportsVideoFrameProgress, isFalse);
      // No frame-capture API: screenshots come from the rendered surface.
      expect(caps.supportsScreenshot, isFalse);
      expect(caps.supportsHwdecInfo, isFalse);
      expect(caps.supportsVideoReconfig, isFalse);
      expect(caps.supportsVideoFilters, isFalse);
      expect(caps.supportsMuteControl, isFalse);
    });
  });

  group('FvpPlayerAdapter', () {
    test('starts without a texture, so availability is honest', () {
      final adapter = FvpPlayerAdapter();
      addTearDown(adapter.dispose);

      expect(adapter.available, isFalse);
      expect(adapter.textureListenable, isA<ValueListenable<int?>>());
      expect(adapter.textureListenable.value, isNull);
    });

    test('the viewport fit follows the shared PlayerVideo contract', () {
      final adapter = FvpPlayerAdapter();
      addTearDown(adapter.dispose);

      expect(adapter.fitListenable.value, BoxFit.contain);

      adapter.setVideoFit(BoxFit.cover);

      expect(adapter.fitListenable.value, BoxFit.cover);
      expect(adapter.videoConfig.fit, BoxFit.cover, reason: 'the open-time config keeps the host choice');
    });

    test('replacing the video config moves the fit notifier only when the fit changed', () {
      final adapter = FvpPlayerAdapter();
      addTearDown(adapter.dispose);

      var notifications = 0;
      adapter.fitListenable.addListener(() => notifications++);

      adapter.videoConfig = const FvpVideoConfig(maxWidth: 1920); // same fit
      expect(notifications, 0);

      adapter.videoConfig = const FvpVideoConfig(fit: BoxFit.fill);
      expect(notifications, 1);
    });
  });

  group('FvpVideoConfig', () {
    test('defaults present the frame without stretching or clamping', () {
      const config = FvpVideoConfig();

      expect(config.fit, BoxFit.contain);
      expect(config.alignment, Alignment.center);
      expect(config.filterQuality, FilterQuality.low);
      expect(config.maxWidth, isNull);
      expect(config.maxHeight, isNull);
      expect(config.fitMaxSize, isTrue);
      expect(config.tunnel, isFalse);
      expect(config.fill, const Color(0xFF000000));
    });

    test('copyWith replaces only the named fields', () {
      const base = FvpVideoConfig(maxWidth: 1920, maxHeight: 1080, tunnel: true);
      final next = base.copyWith(maxHeight: 720);

      expect(next.maxWidth, 1920);
      expect(next.maxHeight, 720);
      expect(next.tunnel, isTrue);
      expect(next.fitMaxSize, isTrue);
    });
  });

  group('FvpAdapterFactory', () {
    test('claims only its own backend id', () {
      const factory = FvpAdapterFactory();

      expect(factory.supports('fvp'), isTrue);
      expect(factory.supports('mpv'), isFalse);
      expect(factory.supports(''), isFalse);
    });

    test('the registration carries capabilities before any adapter exists', () {
      const factory = FvpAdapterFactory();

      final registration = factory.registration(priority: 90);

      expect(registration.id, 'fvp');
      expect(registration.priority, 90);
      expect(registration.capabilities.supportsEngineOptions, isTrue);
    });

    test('created adapters inherit the factory settings', () {
      const factory = FvpAdapterFactory(
        properties: <String, String>{'hwdec': 'auto'},
        videoConfig: FvpVideoConfig(maxWidth: 1280),
      );

      final adapter = factory.create('fvp') as FvpPlayerAdapter;
      addTearDown(adapter.dispose);

      expect(adapter.properties['hwdec'], 'auto');
      expect(adapter.videoConfig.maxWidth, 1280);
      expect(adapter.id, 'fvp');
    });

    test('configure runs once per created instance', () {
      var configured = 0;
      final factory = FvpAdapterFactory(configure: (_) => configured++);

      // Thrown away on purpose: the test counts `configure`, and disposing an
      // adapter that never opened a source has nothing to wait for.
      unawaited((factory.create('fvp') as FvpPlayerAdapter).dispose());
      unawaited((factory.create('fvp') as FvpPlayerAdapter).dispose());

      expect(configured, 2);
    });
  });

  group('registerFvpFactory', () {
    test('a kernel asked for the fvp backend gets one', () {
      final factory = DefaultPlayerAdapterFactory();

      registerFvpFactory(factory);

      expect(factory.supports('fvp'), isTrue);
      expect(factory.create('fvp'), isA<FvpPlayerAdapter>());
    });
  });
}
