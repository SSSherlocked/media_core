import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/player_id.dart';

/// Represents the stable identity of a player.
///
/// [PlayerIdentity] contains only information that belongs to the lifetime of the
/// player identity itself. Runtime associations such as session, request,
/// operation, and generation are intentionally kept outside this object.
///
/// PlayerIdentity equality is determined exclusively by [id].
final class PlayerIdentity extends Equatable {
  /// Creates a player from an existing [PlayerId].
  const PlayerIdentity({required this.id, required this.createdAt});

  /// Creates a new player with a generated unique identifier.
  factory PlayerIdentity.create({DateTime? createdAt}) {
    return PlayerIdentity(id: PlayerId.generate(), createdAt: createdAt ?? clock.now());
  }

  /// Stable identifier of this player instance.
  final PlayerId id;

  /// Time at which this player identity was created.
  ///
  /// This value is informational and does not participate in identity
  /// equality.
  final DateTime createdAt;

  /// Returns whether [other] represents the same player identity.
  ///
  /// PlayerIdentity identity is determined exclusively by [id].
  bool isSamePlayer(PlayerIdentity other) {
    return id == other.id;
  }

  /// Returns whether [other] represents a different player identity.
  bool isDifferentPlayer(PlayerIdentity other) {
    return id != other.id;
  }

  @override
  List<Object> get props => <Object>[id];

  @override
  String toString() {
    return 'PlayerIdentity('
        'id: $id, '
        'createdAt: $createdAt'
        ')';
  }
}
