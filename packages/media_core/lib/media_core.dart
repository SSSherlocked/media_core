// GENERATED PACKAGE LIBRARY - DO NOT EDIT.

/// Public entry point for the `media_core` package.
///
/// This library exports the public module libraries that make up
/// the reusable media core architecture.
///
/// Each module owns its own public library:
///
///   `lib/core/library.dart`
///   `lib/source/library.dart`
///   `lib/adapter/library.dart`
///
/// Generated files such as `*.freezed.dart` and `*.g.dart` are never
/// exported directly.
///
/// Internal modules such as `testing` are intentionally excluded.
///
/// Do not edit manually.
library;

// ============================================================================
// Public modules
// ============================================================================

/// PlayerIdentity backend adapter abstraction and adapter lifecycle..
export 'package:media_core/adapter/library.dart';

/// Audio focus, session, route, volume and mute management..
export 'package:media_core/audio/library.dart';

/// Debugging and fault-injection infrastructure..
export 'package:media_core/bug/library.dart';

/// Memory, disk and cache storage abstractions..
export 'package:media_core/cache/library.dart';

/// Protocol-neutral casting: render devices, transport state, controller..
export 'package:media_core/casting/library.dart';

/// Composition layer: presentation timeline, segments and cues..
export 'package:media_core/composition/library.dart';

/// Mutex, semaphore, locking and concurrency control primitives..
export 'package:media_core/concurrency/library.dart';

/// Cross-module player and playback coordination..
export 'package:media_core/coordinator/library.dart';

/// Public player API and fundamental player models..
export 'package:media_core/core/library.dart';

/// Logging, performance, memory and network diagnostics..
export 'package:media_core/diagnostics/library.dart';

/// Error models, classification, formatting and error policies..
export 'package:media_core/error/library.dart';

/// PlayerIdentity event definitions, dispatching and subscriptions..
export 'package:media_core/event/library.dart';

/// PlayerIdentity and backend factory, registration and selection..
export 'package:media_core/factory/library.dart';

/// Backend, line and quality fallback mechanisms..
export 'package:media_core/fallback/library.dart';

/// Video geometry, orientation, rotation and display dimensions..
export 'package:media_core/geometry/library.dart';

/// Stable cross-module identity and identifier value objects..
export 'package:media_core/identity/library.dart';

/// Background-job outcomes and the reporter slot a notification layer registers into..
export 'package:media_core/job/library.dart';

/// PlayerIdentity kernel: orchestration root wiring source, adapter, session, playback, recovery, fallback, pool and events..
export 'package:media_core/kernel/library.dart';

/// PlayerIdentity, page and application lifecycle management..
export 'package:media_core/lifecycle/library.dart';

/// Network abstraction, monitoring, conditions and metrics..
export 'package:media_core/network/library.dart';

/// High-level asynchronous and business operations..
export 'package:media_core/operation/library.dart';

/// Media source planning: plans, planner contract and defaults..
export 'package:media_core/planning/library.dart';

/// Platform capabilities and platform-specific abstractions..
export 'package:media_core/platform/library.dart';

/// Playback commands, state, position, duration and options..
export 'package:media_core/playback/library.dart';

/// Centralized cross-module player policies..
export 'package:media_core/policy/library.dart';

/// PlayerIdentity instance pooling, allocation and recycling..
export 'package:media_core/pool/library.dart';

/// Media preloading, warm-up and preload scheduling..
export 'package:media_core/preload/library.dart';

/// Fullscreen, picture-in-picture and floating presentation..
export 'package:media_core/presentation/library.dart';

/// Quality candidates and live switching continuity..
export 'package:media_core/quality/library.dart';

/// Reactive abstractions and stream utilities..
export 'package:media_core/reactive/library.dart';

/// Desired-state to actual-state reconciliation..
export 'package:media_core/reconciler/library.dart';

/// Recording abstraction, sessions, formats and backends..
export 'package:media_core/recording/library.dart';

/// Playback recovery, retry scheduling and recovery state..
export 'package:media_core/recovery/library.dart';

/// PlayerIdentity rendering abstraction and rendering state..
export 'package:media_core/renderer/library.dart';

/// Decoder, memory, bandwidth and thermal resource management..
export 'package:media_core/resource/library.dart';

/// Unified result and asynchronous result abstractions..
export 'package:media_core/result/library.dart';
// Composition root: owns adapter + session + per-session controllers.
export 'package:media_core/runtime/library.dart';

/// Frame capture: engine capture, surface capture, captured-frame value, file writing..
export 'package:media_core/screenshot/library.dart';

/// PlayerIdentity session lifecycle, context, state and operations..
export 'package:media_core/session/library.dart';

/// Logical player slot ownership, assignment and state..
export 'package:media_core/slot/library.dart';

/// Media source abstraction, metadata, resolution and validation..
export 'package:media_core/source/library.dart';

/// Generic state-machine infrastructure and state transitions..
export 'package:media_core/state_machine/library.dart';

/// Task execution, scheduling, priority and cancellation..
export 'package:media_core/task/library.dart';

/// Generic reusable utility functions and helpers..
export 'package:media_core/util/library.dart';

/// PlayerIdentity visibility observation, state and management..
export 'package:media_core/visibility/library.dart';
