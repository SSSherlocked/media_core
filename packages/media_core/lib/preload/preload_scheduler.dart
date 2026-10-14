import 'package:media_core/preload/preload_task.dart';

/// Schedules preload tasks.
final class PreloadScheduler {
  final List<PreloadTask> _tasks = [];

  /// The queued tasks in scheduling order, as an unmodifiable view.
  List<PreloadTask> get tasks => List.unmodifiable(_tasks);

  /// Whether any task is waiting to be scheduled.
  bool get hasTasks => _tasks.isNotEmpty;

  /// Queues [task] and re-sorts so higher-priority tasks run first.
  void add(PreloadTask task) {
    task.queue();

    _tasks.add(task);

    _sort();
  }

  /// Removes and returns the highest-priority task, or `null` when empty.
  PreloadTask? next() {
    if (_tasks.isEmpty) {
      return null;
    }

    return _tasks.removeAt(0);
  }

  /// Discards every queued task.
  void clear() {
    _tasks.clear();
  }

  void _sort() {
    _tasks.sort((a, b) {
      return b.priority.index.compareTo(a.priority.index);
    });
  }
}
