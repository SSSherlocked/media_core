import 'dart:async';

import 'package:example/demos/module_demo.dart';
import 'package:example/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detail page for one module demo:
/// bilingual purpose -> runnable output -> source snippet.
class ModuleDemoPage extends StatefulWidget {
  /// Creates the page that runs [demo].
  const new({required this.demo, super.key});

  /// The demo this page shows, runs and prints the source of.
  final ModuleDemo demo;

  @override
  State<ModuleDemoPage> createState() => _ModuleDemoPageState();
}

class _ModuleDemoPageState extends State<ModuleDemoPage> {
  String? _output;
  bool _running = false;
  bool _showCode = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _output = null;
    });
    final buffer = StringBuffer();
    try {
      final result = await widget.demo.run();
      buffer.write(result);
    } on Object catch (error, stack) {
      buffer
        ..writeln('❌ Exception: $error')
        ..writeln(stack.toString());
    }
    if (mounted) {
      setState(() {
        _output = buffer.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = DemoLanguageScope.of(context);
    final isZh = lang == DemoLanguage.zh;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isZh ? widget.demo.nameZh : widget.demo.nameEn),
        actions: [
          IconButton(
            tooltip: isZh ? '切换到英文' : 'Switch to Chinese',
            icon: const Icon(Icons.translate),
            onPressed: () => DemoLanguageScope.toggle(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Purpose card.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        isZh ? '模块说明' : 'What this module does',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(isZh ? widget.demo.purposeZh : widget.demo.purposeEn),
                  const SizedBox(height: 12),
                  Text(
                    isZh ? '关键点' : 'Key points',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  for (final point in isZh ? widget.demo.pointsZh : widget.demo.pointsEn)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(point)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Run card.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.play_circle_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        isZh ? '运行示例' : 'Run the demo',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _running ? null : _run,
                        icon: _running
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.play_arrow, size: 18),
                        label: Text(_running ? (isZh ? '运行中…' : 'Running…') : (isZh ? '运行' : 'Run')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 72),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _output == null
                        ? Text(
                            isZh ? '点击「运行」执行本模块的示例代码。' : 'Press "Run" to execute this module demo.',
                            style: theme.textTheme.bodySmall,
                          )
                        : SelectableText(_output!, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
                  if (_output != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          // The copy is fire-and-forget: the snackbar below is what
                          // the user is meant to look at, and awaiting the platform
                          // channel would only delay it.
                          unawaited(Clipboard.setData(ClipboardData(text: _output!)));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(isZh ? '已复制输出' : 'Output copied')));
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(isZh ? '复制' : 'Copy'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Snippet card.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _showCode = !_showCode),
                    child: Row(
                      children: [
                        Icon(Icons.code, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          isZh ? '示例代码' : 'Snippet',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Icon(_showCode ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                  if (_showCode) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        widget.demo.snippet,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
