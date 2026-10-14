import 'dart:async';

import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart';

/// Failure handling: what the framework does when something breaks.
///
/// Two layers, and they are worth seeing together because they are easy to
/// confuse: *faults* are injected deliberately (to test the paths below them),
/// and *recovery* is what the framework does about a real failure. What the demo
/// shows is the decision, not the plumbing: which faults exist, what error codes
/// are classified as retryable, and how a retry budget behaves.
class FaultDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'fault';

  @override
  ModuleCategory get category => ModuleCategory.failure;

  @override
  String get nameZh => '故障注入与失败分类';

  @override
  String get nameEn => 'Fault injection and failure classification';

  @override
  String get purposeZh =>
      'FaultInjector 按模式与概率注入故障类型（网络不可用、超时、解码失败…），用来验证下游的错误路径而不是等到线上遇到；ErrorPolicy 决定哪些错误可重试、重试几次、退避多久；RetryUtils 提供尝试预算与退避计算。三者共同定义"坏了之后会发生什么"。';

  @override
  String get purposeEn =>
      'FaultInjector injects fault types (network unavailable, timeout, decoder failure…) by mode and probability, so the error paths below it are tested deliberately instead of met in production; ErrorPolicy decides which errors are retryable, how often and with what delay; RetryUtils supplies the budget and the backoff. Together they define what happens after something breaks.';

  @override
  List<String> get pointsZh => const <String>[
    'FaultType 是开放词汇：networkUnavailable / networkTimeout / decoderFailure …',
    'BugModeController 决定注入是否生效（off / 按概率 / 强制），生产构建里保持关闭',
    'ErrorPolicy.defaults() 把网络、超时、源、后端错误标为可重试',
    'PlayerErrorCode / PlayerErrorCategory — 稳定的错误码值对象，不是字符串',
    '恢复阶梯（recovery 模块）按"重开当前源 → 换线路 → 换引擎 → 退避"升级，由 live/player 页面实际演示',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'FaultType is an open vocabulary: networkUnavailable / networkTimeout / decoderFailure …',
    'BugModeController gates injection (off / probabilistic / forced); it stays off in production builds',
    'ErrorPolicy.defaults() marks network, timeout, source and backend errors as retryable',
    'PlayerErrorCode / PlayerErrorCategory — stable value objects, not strings',
    'The recovery ladder (recovery module) escalates reopen → next line → next backend → backoff, demonstrated live by the live and player pages',
  ];

  @override
  String get snippet => '''
final injector = FaultInjector(modeController: mode);

if (injector.canInject(FaultConfig(type: FaultType.networkTimeout, probability: 0.5))) {
  await injector.inject(FaultConfig(type: FaultType.networkTimeout));
}

final policy = ErrorPolicy.defaults();
if (policy.isRetryable(PlayerErrorCode.networkTimeout)) {
  await RetryUtils.run(open, maxAttempts: policy.maxRetries, delay: policy.retryDelay);
}
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    _faultCatalogue(buffer);
    await _injectionSection(buffer);
    _errorPolicySection(buffer);
    await _budgetSection(buffer);

    return buffer.toString();
  }

  /// What can be injected at all.
  void _faultCatalogue(StringBuffer buffer) {
    const shown = <FaultType>[
      FaultType.networkUnavailable,
      FaultType.networkTimeout,
      FaultType.connectionFailure,
      FaultType.sourceFailure,
      FaultType.decoderFailure,
      FaultType.demuxerFailure,
      FaultType.mediaCorruption,
      FaultType.rendererFailure,
      FaultType.audioFailure,
      FaultType.recordingFailure,
      FaultType.resourceExhaustion,
      FaultType.memoryPressure,
    ];

    buffer.writeln('fault vocabulary (a value object, so a host can add its own):');

    for (final fault in shown) {
      buffer.writeln('  ${fault.value.padRight(22)}${fault.isNetworkRelated ? 'network-related' : ''}');
    }

    buffer
      ..writeln('  → an injected fault is how a host proves its own error UI works without')
      ..writeln('    unplugging the network: the injector sits above the real failure paths.')
      ..writeln();
  }

  /// Injection gated by mode and probability.
  Future<void> _injectionSection(StringBuffer buffer) async {
    // BugModeConfig decides whether injection is allowed at all, and it gates by
    // category: a network fault is disruptive, so a mode that allows only
    // deterministic faults refuses it. The named levels spell out what each one
    // permits, and `aggressive` is the one that allows everything but chaos.
    final mode = BugModeController(config: BugModeConfig.aggressive);
    // A hook is the *call site*, not the fault: it declares which fault types it
    // can carry, and performing one is its job. Without a hook nothing can be
    // injected at all, which is the framework saying "a fault needs somewhere to
    // happen" rather than inventing a place for it.
    final hook = _DemoLiveHook();
    final hooks = BugHooks(hooks: <BugHook>[hook]);
    final injector = FaultInjector(modeController: mode, hooks: hooks);

    buffer
      ..writeln('BugModeConfig.aggressive (disruptive + stress + random; not chaos), one hook registered:')
      ..writeln(
        '  the hook supports network faults: '
        '${hooks.canInject(const FaultConfig(type: FaultType.networkTimeout))}',
      );

    const config = FaultConfig(type: FaultType.networkTimeout, delay: Duration(milliseconds: 50));

    if (injector.canInject(config)) {
      final pending = injector.inject(config, source: 'live', target: 'line-2');
      buffer.writeln('  while the hook runs: hasActiveFaults=${injector.hasActiveFaults}');

      final event = await pending;
      buffer
        ..writeln('  injected: ${event.type.value} from=${event.source} target=${event.target}')
        ..writeln('  the hook ran: ${hook.triggered} time(s), faultId=${event.faultId}')
        ..writeln(
          '  after it returns: hasActiveFaults=${injector.hasActiveFaults} '
          '(a fault is "active" only while it is applied)',
        );
      injector.clearActiveFaults();
      buffer.writeln('  clearActiveFaults() → ${injector.hasActiveFaults}');
    } else {
      buffer.writeln('  canInject=false: the mode or the hooks refused this fault');
    }

    // The same injector with injection off: what production looks like.
    final offInjector = FaultInjector(
      modeController: BugModeController(),
      hooks: BugHooks(hooks: <BugHook>[_DemoLiveHook()]),
    );

    buffer
      ..writeln('BugModeConfig.disabled — the production default:')
      ..writeln('  canInject=${offInjector.canInject(config)}, tryInject=${await offInjector.tryInject(config)}')
      ..writeln('  → tryInject returns null instead of throwing: the call site stays readable')
      ..writeln('    when injection is a debug-only branch.');

    injector.dispose();
    offInjector.dispose();

    buffer.writeln();
  }

  /// Which failures are worth retrying.
  void _errorPolicySection(StringBuffer buffer) {
    final policy = ErrorPolicy.defaults();

    buffer.writeln(
      'ErrorPolicy.defaults(): maxRetries=${policy.maxRetries}, '
      'retryDelay=${policy.retryDelay.inMilliseconds}ms, '
      'retryable codes=${policy.retryable.length}',
    );

    final codes = <PlayerErrorCode>[
      PlayerErrorCode.networkUnavailable,
      PlayerErrorCode.networkTimeout,
      PlayerErrorCode.sourceResolveFailed,
      PlayerErrorCode.decoderError,
      PlayerErrorCode.sourceMissing,
      PlayerErrorCode.invalidArgument,
    ];

    for (final code in codes) {
      // A policy answers for a *failure*, not a code alone: the same code can
      // be retryable or not depending on the context and the attempt count.
      final decision = policy.shouldRetry(PlayerFailure.fromCode(code));
      final exhausted = policy.shouldRetry(PlayerFailure.fromCode(code), retryCount: policy.maxRetries);

      buffer.writeln(
        '  ${code.value.padRight(28)} retry=${decision.toString().padRight(5)} '
        'after ${policy.maxRetries} retries=${exhausted ? 'retry' : 'stop'}',
      );
    }

    buffer
      ..writeln('  → the classification lives in one place on purpose: a retry decided at')
      ..writeln('    four call sites is four different opinions about what "temporary" means,')
      ..writeln('    and the attempt count is part of the answer.')
      ..writeln();
  }

  /// A budget, and what spending it looks like.
  Future<void> _budgetSection(StringBuffer buffer) async {
    var attempts = 0;
    final delays = <int>[];

    buffer.writeln('a network that stays down, with maxRetries=3:');

    try {
      await RetryUtils.run<void>(
        () async {
          attempts++;
          throw StateError('network still down');
        },
        shouldRetry: (error, stackTrace, attempt) {
          delays.add(RetryUtils.backoff(attempt).inMilliseconds);
          return RetryUtils.until(3)(error, stackTrace, attempt);
        },
      );
    } on Object catch (error) {
      buffer
        ..writeln('  attempts=$attempts, backoff between them: ${delays.join('ms, ')}ms')
        ..writeln('  final error: $error')
        ..writeln('  → the budget is what turns "retry forever" into "fail after ~2s and tell someone".');
    }

    // Not every failure deserves a retry.
    var refused = 0;
    try {
      await RetryUtils.run<void>(() async {
        refused++;
        throw StateError('source is gone');
      }, shouldRetry: RetryUtils.never);
    } on Object catch (_) {
      buffer
        ..writeln()
        ..writeln('a source that no longer exists, with RetryUtils.never:')
        ..writeln('  attempts=$refused — a retry would fetch the same 404 three times.');
    }
  }
}

/// A hook standing in for a real call site.
///
/// In an application this would be the live controller's line switch or the
/// adapter's open path: somewhere a fault can actually be applied. The demo only
/// needs it to prove the seam — mode allows it, the hook supports it, and
/// [FaultInjector.inject] reaches the hook.
final class _DemoLiveHook implements BugHook {
  /// How many times the injected fault was applied.
  int triggered = 0;

  @override
  String get name => 'demo.live';

  @override
  bool supports(FaultConfig config) => config.type.isNetworkRelated;

  @override
  FutureOr<void> onFault(FaultConfig config, {String? target, Object? metadata}) async {
    triggered++;

    // A real hook does the disruptive thing here — fail the request, stall the
    // read — and waits for the configured delay so the fault covers a window
    // rather than an instant.
    final delay = config.delay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
  }
}
