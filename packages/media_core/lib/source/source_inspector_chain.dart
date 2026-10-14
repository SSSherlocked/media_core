import 'package:media_core/core/player_info.dart';
import 'package:media_core/source/source_inspect_context.dart';
import 'package:media_core/source/source_inspector.dart';
import 'package:media_core/source/source_resolved.dart';

/// Inspects a [ResolvedSource] by selecting the first compatible inspector.
///
/// The chain is responsible only for inspector selection and orchestration.
/// It does not perform retry, recovery, fallback, or player creation.
///
/// Inspector order is significant: the first inspector that supports the
/// source is selected.
final class SourceInspectorChain implements SourceInspector {
  /// Creates a chain seeded with [inspectors], in inspection order.
  SourceInspectorChain({Iterable<SourceInspector> inspectors = const []})
    : _inspectors = List<SourceInspector>.from(inspectors);

  final List<SourceInspector> _inspectors;

  /// Returns the currently registered inspectors.
  List<SourceInspector> get inspectors => List<SourceInspector>.unmodifiable(_inspectors);

  /// Number of registered inspectors.
  int get length => _inspectors.length;

  /// Whether the chain contains no inspectors.
  bool get isEmpty => _inspectors.isEmpty;

  /// Whether the chain contains at least one inspector.
  bool get isNotEmpty => _inspectors.isNotEmpty;

  /// Adds [inspector] to the end of the chain.
  ///
  /// Duplicate inspector instances are ignored.
  void add(SourceInspector inspector) {
    if (_inspectors.contains(inspector)) {
      return;
    }

    _inspectors.add(inspector);
  }

  /// Inserts [inspector] at [index].
  ///
  /// Duplicate inspector instances are ignored.
  void insert(int index, SourceInspector inspector) {
    if (_inspectors.contains(inspector)) {
      return;
    }

    _inspectors.insert(index, inspector);
  }

  /// Removes [inspector] from the chain.
  bool remove(SourceInspector inspector) {
    return _inspectors.remove(inspector);
  }

  /// Removes all registered inspectors.
  void clear() {
    _inspectors.clear();
  }

  /// Moves [inspector] to the front of the chain.
  ///
  /// This is useful when a more specific inspector should take precedence
  /// over a generic inspector.
  bool prioritize(SourceInspector inspector) {
    final index = _inspectors.indexOf(inspector);

    if (index < 0) {
      return false;
    }

    if (index == 0) {
      return true;
    }

    _inspectors
      ..removeAt(index)
      ..insert(0, inspector);
    return true;
  }

  /// Returns the first inspector that supports [source].
  SourceInspector? findInspector(ResolvedSource source) {
    for (final inspector in _inspectors) {
      if (inspector.supports(source)) {
        return inspector;
      }
    }

    return null;
  }

  /// Returns all inspectors that support [source], preserving registration
  /// order.
  Iterable<SourceInspector> matchingInspectors(ResolvedSource source) sync* {
    for (final inspector in _inspectors) {
      if (inspector.supports(source)) {
        yield inspector;
      }
    }
  }

  @override
  bool supports(ResolvedSource source) {
    return findInspector(source) != null;
  }

  @override
  Future<PlayerInfo> inspect(ResolvedSource source, {SourceInspectContext context = SourceInspectContext.empty}) {
    final inspector = findInspector(source);

    if (inspector == null) {
      // Delivered through the returned Future, as an `async` body did, so
      // no caller ever sees this failure thrown synchronously.
      return Future<PlayerInfo>.error(StateError('No source inspector supports source: ${source.uri}'));
    }

    return inspector.inspect(source, context: context);
  }
}
