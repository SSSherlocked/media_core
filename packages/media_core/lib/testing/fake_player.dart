import 'package:clock/clock.dart';

import 'package:media_core/core/player_identity.dart';
import 'package:media_core/identity/player_id.dart';

/// Deterministic [PlayerIdentity] builder for tests.
///
/// Builds stable player identities from integer seeds so
/// assertions do not depend on generated identifiers.
final class FakePlayer {
  /// Builds a player from [seed].
  ///
  /// The same seed always produces the same [PlayerId].
  factory FakePlayer.fromSeed(int seed) => FakePlayer._(seed);
  const FakePlayer._(this._seed);

  final int _seed;

  /// PlayerIdentity identity for this fake.
  PlayerIdentity get player =>
      PlayerIdentity(id: PlayerId('fake-player-$_seed'), createdAt: DateTime.fromMillisecondsSinceEpoch(_seed));

  /// Generated player identity with a random id.
  static PlayerIdentity generate({DateTime? createdAt}) {
    return PlayerIdentity.create(createdAt: createdAt ?? clock.now());
  }

  /// Builds multiple players.
  static List<PlayerIdentity> seeds(Iterable<int> seeds) {
    return seeds.map((seed) => FakePlayer._(seed).player).toList(growable: false);
  }
}
