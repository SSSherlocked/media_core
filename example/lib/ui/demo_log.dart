import 'package:flutter/material.dart';

/// A tiny in-page event log.
///
/// Every demo page shows what the framework reported while the developer
/// pressed buttons — adapter events, recovery decisions, download progress.
/// A log is the cheapest honest way to make framework behaviour visible
/// without inventing a UI for each module.
final class DemoLog extends ChangeNotifier {
  /// Creates a log that keeps the last [maxLines] lines.
  new({this.maxLines = 200});

  /// How many lines are kept.
  final int maxLines;

  final List<_LogLine> _lines = <_LogLine>[];

  /// Most recent line first.
  List<String> get lines => _lines.map((line) => line.render()).toList(growable: false);

  /// Whether anything was logged.
  bool get isEmpty => _lines.isEmpty;

  /// Adds one line, timestamped to the second.
  ///
  /// A repeat of the line already on top is counted rather than appended:
  /// position events arrive about four times a second, and uncollapsed they
  /// pushed every button press and recovery decision out of the window in
  /// under a minute — which is the opposite of what this panel is for.
  void add(String message) {
    final head = _lines.isEmpty ? null : _lines.first;

    if (head != null && head.message == message) {
      _lines[0] = (at: DateTime.now(), message: message, count: head.count + 1);
    } else {
      _lines.insert(0, (at: DateTime.now(), message: message, count: 1));

      while (_lines.length > maxLines) {
        _lines.removeLast();
      }
    }

    notifyListeners();
  }

  /// Clears the log.
  void clear() {
    _lines.clear();
    notifyListeners();
  }
}

typedef _LogLine = ({DateTime at, String message, int count});

extension on _LogLine {
  String render() {
    final stamp =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';

    return count == 1 ? '$stamp  $message' : '$stamp  $message  ×$count';
  }
}

/// Shows a [DemoLog] as a scrolling monospace panel.
class DemoLogPanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.log, super.key, this.height = 180});

  /// The log to render.
  final DemoLog log;

  /// Panel height.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: AnimatedBuilder(
          animation: log,
          builder: (context, _) {
            if (log.isEmpty) {
              return const Center(
                child: Text('事件日志 / event log', style: TextStyle(fontSize: 12, color: Colors.grey)),
              );
            }

            return ListView.builder(
              itemCount: log.lines.length,
              itemBuilder: (context, index) =>
                  Text(log.lines[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            );
          },
        ),
      ),
    );
  }
}
