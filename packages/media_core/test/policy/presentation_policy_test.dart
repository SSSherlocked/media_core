import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/policy/presentation_policy.dart';

void main() {
  const base = PresentationPolicy();

  /// One case per field: flipping it alone must make the policy a different
  /// value. A field the equality does not list compares equal to `base`, so a
  /// host that forbids that mode is silently overruled by the cache of the
  /// previous one.
  final fields =
      <
        ({
          String name,
          PresentationPolicy Function(PresentationPolicy policy) flip,
          bool Function(PresentationPolicy policy) read,
        })
      >[
        (name: 'enabled', flip: (p) => p.copyWith(enabled: false), read: (p) => p.enabled),
        (name: 'allowFullscreen', flip: (p) => p.copyWith(allowFullscreen: false), read: (p) => p.allowFullscreen),
        (
          name: 'allowWindowFullscreen',
          flip: (p) => p.copyWith(allowWindowFullscreen: false),
          read: (p) => p.allowWindowFullscreen,
        ),
        (
          name: 'allowPictureInPicture',
          flip: (p) => p.copyWith(allowPictureInPicture: false),
          read: (p) => p.allowPictureInPicture,
        ),
        (
          name: 'allowFloatingWindow',
          flip: (p) => p.copyWith(allowFloatingWindow: false),
          read: (p) => p.allowFloatingWindow,
        ),
        (
          name: 'autoFullscreenOnLandscape',
          flip: (p) => p.copyWith(autoFullscreenOnLandscape: true),
          read: (p) => p.autoFullscreenOnLandscape,
        ),
        (
          name: 'autoExitFullscreenOnPortrait',
          flip: (p) => p.copyWith(autoExitFullscreenOnPortrait: true),
          read: (p) => p.autoExitFullscreenOnPortrait,
        ),
        (
          name: 'lockOrientationInFullscreen',
          flip: (p) => p.copyWith(lockOrientationInFullscreen: false),
          read: (p) => p.lockOrientationInFullscreen,
        ),
        (
          name: 'hideSystemUiInFullscreen',
          flip: (p) => p.copyWith(hideSystemUiInFullscreen: false),
          read: (p) => p.hideSystemUiInFullscreen,
        ),
        (
          name: 'restoreSystemUiAfterExit',
          flip: (p) => p.copyWith(restoreSystemUiAfterExit: false),
          read: (p) => p.restoreSystemUiAfterExit,
        ),
      ];

  group('PresentationPolicy equality', () {
    test('the fixture is the all-defaults policy it claims to be', () {
      expect(base.enabled, isTrue);
      expect(base.allowFullscreen, isTrue);
      expect(base.allowWindowFullscreen, isTrue);
    });

    test('every field takes part in ==', () {
      for (final field in fields) {
        final other = field.flip(base);
        expect(field.read(other), isNot(field.read(base)), reason: '${field.name} did not actually change.');
        expect(other, isNot(base), reason: 'A policy differing only in ${field.name} is a different policy.');
        expect(other.hashCode, isNot(base.hashCode), reason: '${field.name} is missing from hashCode.');
      }
    });

    test('two policies built the same way are equal', () {
      const left = PresentationPolicy.mobile();
      const right = PresentationPolicy.mobile();

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('copyWith keeps the fields it was not given', () {
      final next = base.copyWith(allowWindowFullscreen: false);

      expect(next.allowWindowFullscreen, isFalse);
      expect(next.allowFullscreen, isTrue);
      expect(next.allowPictureInPicture, isTrue);
    });
  });
}
