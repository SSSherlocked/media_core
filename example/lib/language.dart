import 'package:flutter/material.dart';

/// Application-wide language mode for demo descriptions.
enum DemoLanguage {
  /// Simplified Chinese, the default every demo description renders in.
  zh,

  /// English, flipped on so a Latin-script reader can follow the demos.
  en,
}

/// Simple inherited language state with a toggle.
class DemoLanguageScope extends InheritedNotifier<DemoLanguageNotifier> {
  /// Wires [notifier] below [child] so any descendant can read and flip it.
  const new({required DemoLanguageNotifier notifier, required super.child, super.key}) : super(notifier: notifier);

  /// Reads the active language and rebuilds the calling widget when it changes.
  static DemoLanguage of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DemoLanguageScope>();
    return scope?.notifier?.value ?? DemoLanguage.zh;
  }

  /// Toggles the language from anywhere below the scope.
  static void toggle(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DemoLanguageScope>();
    scope?.notifier?.toggle();
  }
}

/// ChangeNotifier that owns the one language the whole demo app shows in.
class DemoLanguageNotifier extends ChangeNotifier {
  /// Creates the notifier, starting from the language passed in.
  new(this._value);

  DemoLanguage _value;

  /// The language every bilingual demo label is currently drawn in.
  DemoLanguage get value => _value;

  /// Flips Chinese/English and wakes the pages that listen so they repaint.
  void toggle() {
    _value = _value == DemoLanguage.zh ? DemoLanguage.en : DemoLanguage.zh;
    notifyListeners();
  }
}
