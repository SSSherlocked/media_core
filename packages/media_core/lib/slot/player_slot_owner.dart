import 'package:equatable/equatable.dart';

/// Identifies the owner of a player slot.
///
/// A slot owner represents the module or component
/// currently using a slot.
///
/// It does not:
///
/// - manage slot lifecycle
/// - allocate players
/// - control playback
///
/// Those belong to:
///
/// - PlayerSlotManager
/// - PlayerPool
final class PlayerSlotOwner extends Equatable {
  /// Creates a slot owner.
  const PlayerSlotOwner({required this.type, this.id});

  /// Creates page owner.
  factory PlayerSlotOwner.page(String id) {
    return PlayerSlotOwner(type: PlayerSlotOwnerType.page, id: id);
  }

  /// Creates preload owner.
  factory PlayerSlotOwner.preload(String id) {
    return PlayerSlotOwner(type: PlayerSlotOwnerType.preload, id: id);
  }

  /// Creates PIP owner.
  factory PlayerSlotOwner.pip() {
    return const PlayerSlotOwner(type: PlayerSlotOwnerType.pip);
  }

  /// Creates system owner.
  factory PlayerSlotOwner.system() {
    return const PlayerSlotOwner(type: PlayerSlotOwnerType.system);
  }

  /// Owner type.
  final PlayerSlotOwnerType type;

  /// Optional owner identifier.
  ///
  /// Examples:
  ///
  /// - page id
  /// - widget id
  /// - preload task id
  final String? id;

  /// Whether owner is page.
  bool get isPage {
    return type == PlayerSlotOwnerType.page;
  }

  /// Whether owner is preload.
  bool get isPreload {
    return type == PlayerSlotOwnerType.preload;
  }

  /// Whether owner is PIP.
  bool get isPip {
    return type == PlayerSlotOwnerType.pip;
  }

  @override
  List<Object?> get props => [type, id];

  @override
  String toString() {
    return 'PlayerSlotOwner('
        'type=$type, '
        'id=$id'
        ')';
  }
}

/// Slot owner category.
enum PlayerSlotOwnerType {
  /// UI page.
  page,

  /// Preload system.
  preload,

  /// Picture-in-picture.
  pip,

  /// Internal system.
  system,
}
