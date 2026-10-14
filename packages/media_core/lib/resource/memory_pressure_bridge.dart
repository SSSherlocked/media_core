import 'package:media_core/resource/resource_pressure.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Translates the memory package's pressure into the resource layer's.
///
/// Memory pressure is defined in `media_core_memory` (which does not depend on
/// the resource layer), and the resource coordinator folds it together with
/// decoder, bandwidth and thermal pressure. This is the single place where the
/// two vocabularies meet:
///
/// | memory      | resource    |
/// | ----------- | ----------- |
/// | `normal`    | `none`      |
/// | `elevated`  | `warning`   |
/// | `critical`  | `critical`  |
/// | `emergency` | `emergency` |
extension MemoryPressureResourceBridge on MemoryPressure {
  /// This level expressed as a [ResourcePressure].
  ResourcePressure get asResourcePressure => switch (this) {
    MemoryPressure.normal => ResourcePressure.none,
    MemoryPressure.elevated => ResourcePressure.warning,
    MemoryPressure.critical => ResourcePressure.critical,
    MemoryPressure.emergency => ResourcePressure.emergency,
  };
}

/// Translates a [MemoryManager]'s current pressure.
extension MemoryManagerResourceBridge on MemoryManager {
  /// Current memory pressure as a [ResourcePressure].
  ResourcePressure get resourcePressure => pressure.asResourcePressure;
}
