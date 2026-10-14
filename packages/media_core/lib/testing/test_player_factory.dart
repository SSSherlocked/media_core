import 'package:media_core/adapter/player_adapter_context.dart';
import 'package:media_core/adapter/player_adapter_factory.dart';
import 'package:media_core/core/player_identity.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/testing/fake_player.dart';
import 'package:media_core/testing/fake_player_adapter.dart';

/// Convenience builders for players and adapters in tests.
final class TestPlayerFactory {
  const TestPlayerFactory._();

  /// Builds a [PlayerIdentity] with a deterministic id from [seed].
  static PlayerIdentity player(int seed) => FakePlayer.fromSeed(seed).player;

  /// Builds [count] distinct players.
  static List<PlayerIdentity> players(int count) {
    return List<PlayerIdentity>.generate(count, TestPlayerFactory.player, growable: false);
  }

  /// Builds a [PlayerId] from a raw string.
  static PlayerId playerId(String value) => PlayerId(value);

  /// Builds a minimal adapter context for [playerId].
  static PlayerAdapterContext context({String? playerId, String? sessionId}) {
    return PlayerAdapterContext.basic(
      playerId: PlayerId(playerId ?? 'test-player'),
      sessionId: SessionId(sessionId ?? 'test-session'),
    );
  }

  /// Builds a default fake adapter.
  static FakePlayerAdapter fakeAdapter() => FakePlayerAdapter();

  /// Builds a core [PlayerAdapterFactory] that creates fake adapters.
  static DefaultPlayerAdapterFactory fakeAdapterFactory() {
    return DefaultPlayerAdapterFactory()..register('fake', FakePlayerAdapter.new);
  }
}
