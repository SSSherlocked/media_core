import 'package:media_core/audio/audio_focus.dart' show AudioFocus;

/// Platform-independent audio session abstraction.
///
/// An audio session represents the system-level audio environment required by
/// media playback. It is intentionally separate from [AudioFocus]:
///
/// - [AudioSession] manages the lifetime/configuration of the audio session.
/// - [AudioFocus] manages the application's temporary ownership of audio
///   focus.
///
/// The implementation is responsible for translating these operations into
/// the native audio APIs of the target platform.
///
/// No Flutter platform channel or native API should be referenced from this
/// interface. Platform implementations can be provided by the platform layer
/// and injected into the media core.
abstract interface class AudioSession {
  /// Activates the audio session.
  ///
  /// Implementations should configure and activate the native audio session
  /// required for media playback before completing this operation.
  ///
  /// Calling [activate] while the session is already active should be
  /// idempotent where possible.
  Future<void> activate();

  /// Deactivates the audio session.
  ///
  /// Implementations should release or deactivate any system-level audio
  /// resources owned by the session.
  ///
  /// Calling [deactivate] while the session is already inactive should be
  /// harmless.
  Future<void> deactivate();
}
