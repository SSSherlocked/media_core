import 'package:example/language.dart';
import 'package:example/ui/demo_log.dart';
import 'package:flutter/material.dart';

/// Shared shell for the runnable demo pages.
///
/// Keeps the pages themselves about *what is being demonstrated*: the app bar,
/// the event log panel and the action row live here, so every page reads the
/// same way and a developer always knows where the framework's own output is.
class DemoPageScaffold extends StatelessWidget {
  /// Creates the shell.
  const new({
    required this.title,
    required this.log,
    required this.child,
    super.key,
    this.subtitle,
    this.actions = const <Widget>[],
    this.logHeight = 170,
  });

  /// Page title.
  final String title;

  /// One-line explanation under the title.
  final String? subtitle;

  /// Framework log shown at the bottom.
  final DemoLog log;

  /// Page content.
  final Widget child;

  /// Buttons under the content.
  final List<Widget> actions;

  /// Height of the log panel.
  final double logHeight;

  @override
  Widget build(BuildContext context) {
    final isZh = DemoLanguageScope.of(context) == DemoLanguage.zh;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: isZh ? '清空日志' : 'Clear log',
            onPressed: log.clear,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: actions),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: DemoLogPanel(log: log, height: logHeight),
          ),
        ],
      ),
    );
  }
}
