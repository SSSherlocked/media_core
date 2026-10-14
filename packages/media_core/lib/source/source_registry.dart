import 'package:media_core/source/source_inspector.dart';
import 'package:media_core/source/source_inspector_chain.dart';
import 'package:media_core/source/source_resolver.dart';
import 'package:media_core/source/source_resolver_chain.dart';
import 'package:media_core/source/source_service.dart';

/// Registry for source-layer implementations.
///
/// [SourceRegistry] owns the registered resolvers and inspectors and can
/// build a [SourceService] from them.
///
/// It does not perform source resolution or inspection itself.
final class SourceRegistry {
  /// Creates a registry seeded with [resolvers] and [inspectors].
  ///
  /// Both lists keep insertion order, because the chains they build
  /// pick the first implementation that supports a source.
  SourceRegistry({Iterable<SourceResolver> resolvers = const [], Iterable<SourceInspector> inspectors = const []})
    : _resolvers = List<SourceResolver>.from(resolvers),
      _inspectors = List<SourceInspector>.from(inspectors);

  final List<SourceResolver> _resolvers;
  final List<SourceInspector> _inspectors;

  /// Returns the registered resolvers.
  List<SourceResolver> get resolvers => List<SourceResolver>.unmodifiable(_resolvers);

  /// Returns the registered inspectors.
  List<SourceInspector> get inspectors => List<SourceInspector>.unmodifiable(_inspectors);

  /// Number of registered resolvers.
  int get resolverCount => _resolvers.length;

  /// Number of registered inspectors.
  int get inspectorCount => _inspectors.length;

  /// Whether at least one resolver is registered.
  bool get hasResolvers => _resolvers.isNotEmpty;

  /// Whether at least one inspector is registered.
  bool get hasInspectors => _inspectors.isNotEmpty;

  /// Registers [resolver].
  ///
  /// Duplicate instances are ignored.
  void addResolver(SourceResolver resolver) {
    if (_resolvers.contains(resolver)) {
      return;
    }

    _resolvers.add(resolver);
  }

  /// Registers [inspector].
  ///
  /// Duplicate instances are ignored.
  void addInspector(SourceInspector inspector) {
    if (_inspectors.contains(inspector)) {
      return;
    }

    _inspectors.add(inspector);
  }

  /// Removes [resolver].
  bool removeResolver(SourceResolver resolver) {
    return _resolvers.remove(resolver);
  }

  /// Removes [inspector].
  bool removeInspector(SourceInspector inspector) {
    return _inspectors.remove(inspector);
  }

  /// Removes all registered resolvers.
  void clearResolvers() {
    _resolvers.clear();
  }

  /// Removes all registered inspectors.
  void clearInspectors() {
    _inspectors.clear();
  }

  /// Creates a source service from the current registrations.
  ///
  /// The returned service owns its chains, so later registry changes do not
  /// affect an already-created service.
  SourceService createService() {
    return SourceService(
      resolverChain: SourceResolverChain(resolvers: _resolvers),
      inspectorChain: SourceInspectorChain(inspectors: _inspectors),
    );
  }
}
