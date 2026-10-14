import 'package:example/demos/module_demo.dart';
import 'package:example/demos/registry.dart';
import 'package:example/demos/runnable_demo.dart';
import 'package:example/language.dart';
import 'package:example/ui/module_demo_page.dart';
import 'package:flutter/material.dart';

/// Home page: the runnable demos, then the module tour grouped by category.
///
/// The order is deliberate. A developer opening the example wants to see a
/// player play first; the printed module tour is the reference material behind
/// it, not the entry point.
class ModuleCatalogPage extends StatelessWidget {
  /// Creates the page.
  const new({required this.entries, super.key});

  /// Runnable demo pages, in display order.
  final List<RunnableDemo> entries;

  @override
  Widget build(BuildContext context) {
    final isZh = DemoLanguageScope.of(context) == DemoLanguage.zh;

    return Scaffold(
      appBar: AppBar(title: Text(isZh ? 'media_core 示例' : 'media_core example'), actions: const [_LanguageToggle()]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader(
            title: isZh ? '可运行示例' : 'Runnable demos',
            note: isZh
                ? '多数会真的创建播放器并播放媒体；内存与多画面两个页面完全离线'
                : 'most create a player and actually play media; memory and multiview run fully offline',
          ),
          for (final demo in entries)
            ListTile(
              leading: Text(
                demo.id,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
              ),
              title: Text(isZh ? demo.nameZh : demo.nameEn),
              subtitle: Text(isZh ? demo.purposeZh : demo.purposeEn, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: demo.builder)),
            ),
          for (final category in ModuleCategory.values)
            if (hasModuleDemos(category)) ...<Widget>[
              _SectionHeader(
                title: isZh ? category.labelZh : category.labelEn,
                note: isZh ? '运行后打印模块的实际行为' : 'running these prints what the module actually did',
                compact: true,
              ),
              for (final demo in moduleDemosByCategory[category]!)
                ListTile(
                  leading: Text(
                    demo.id,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  title: Text(isZh ? demo.nameZh : demo.nameEn),
                  subtitle: Text(isZh ? demo.purposeZh : demo.purposeEn, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(builder: (_) => ModuleDemoPage(demo: demo)),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

/// Section title with a one-line explanation of what the section's entries do.
class _SectionHeader extends StatelessWidget {
  const new({required this.title, required this.note, this.compact = false});

  final String title;
  final String note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 20 : 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
          ),
          Text(note, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// App-bar language switch.
class _LanguageToggle extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final language = DemoLanguageScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ActionChip(
        avatar: const Icon(Icons.translate, size: 18),
        label: Text(language == DemoLanguage.zh ? 'EN' : '中文'),
        onPressed: () => DemoLanguageScope.toggle(context),
      ),
    );
  }
}
