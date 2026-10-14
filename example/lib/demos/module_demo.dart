/// Base contract every module demo implements.
///
/// A demo bundles:
/// - bilingual metadata (name / purpose / key points)
/// - a representative Dart snippet
/// - a runnable function that produces console-style output
abstract class ModuleDemo {
  /// Const constructor shared by every demo so hosts can register `const` instances.
  const new();

  /// Stable identifier, e.g. `identity`.
  String get id;

  /// Catalog group the module belongs to.
  ModuleCategory get category;

  /// Display name in Chinese, how the home page lists the demo by default.
  String get nameZh;

  /// Display name in English, shown when the app runs in an English locale.
  String get nameEn;

  /// What this module is for, in Chinese (2-4 sentences).
  String get purposeZh;

  /// What this module is for, in English (2-4 sentences).
  String get purposeEn;

  /// Key classes and usage points, in Chinese; the detail page lists them.
  List<String> get pointsZh;

  /// Key classes and usage points, in English; the detail page lists them.
  List<String> get pointsEn;

  /// Representative Dart snippet shown in the page.
  String get snippet;

  /// Runs the demo and returns console-style output.
  Future<String> run();
}

/// Catalog groups shown on the home page.
enum ModuleCategory {
  /// Core value objects and primitives every other module is built on.
  foundation('基础模型', 'Foundation'),

  /// The open → decode → render path and the services wrapped around it.
  playbackChain('播放链路', 'Playback chain'),

  /// Queues, scheduling and the policy decisions that drive them.
  control('控制与策略', 'Control & policy'),

  /// Fault injection, failure classification and recovery.
  failure('失败处理', 'Failure handling'),

  /// Optional capabilities layered on top: recording, download, PiP and more.
  capability('能力扩展', 'Capabilities');

  new(this.labelZh, this.labelEn);

  /// Category label shown on the home page, in Chinese.
  final String labelZh;

  /// Category label shown on the home page, in English.
  final String labelEn;
}
