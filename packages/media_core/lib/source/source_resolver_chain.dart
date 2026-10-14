import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_resolve_context.dart';
import 'package:media_core/source/source_resolved.dart';
import 'package:media_core/source/source_resolver.dart';

/// Resolves a [PlayerSource] by trying registered resolvers in order.
///
/// The chain is responsible only for resolver orchestration. It does not
/// perform recovery, fallback policy, retry, or player creation.
///
/// Resolver order is significant: the first resolver that supports the
/// source is selected.
final class SourceResolverChain implements SourceResolver {
  /// Creates a chain seeded with [resolvers], in resolution order.
  SourceResolverChain({Iterable<SourceResolver> resolvers = const []})
    : _resolvers = List<SourceResolver>.from(resolvers);

  final List<SourceResolver> _resolvers;

  /// Returns the currently registered resolvers.
  List<SourceResolver> get resolvers => List<SourceResolver>.unmodifiable(_resolvers);

  /// Number of registered resolvers.
  int get length => _resolvers.length;

  /// Whether the chain contains no resolvers.
  bool get isEmpty => _resolvers.isEmpty;

  /// Whether the chain contains at least one resolver.
  bool get isNotEmpty => _resolvers.isNotEmpty;

  /// Adds [resolver] to the end of the chain.
  ///
  /// Duplicate resolver instances are ignored.
  void add(SourceResolver resolver) {
    if (_resolvers.contains(resolver)) {
      return;
    }

    _resolvers.add(resolver);
  }

  /// Inserts [resolver] at [index].
  ///
  /// Duplicate resolver instances are ignored.
  void insert(int index, SourceResolver resolver) {
    if (_resolvers.contains(resolver)) {
      return;
    }

    _resolvers.insert(index, resolver);
  }

  /// Removes [resolver] from the chain.
  bool remove(SourceResolver resolver) {
    return _resolvers.remove(resolver);
  }

  /// Removes all registered resolvers.
  void clear() {
    _resolvers.clear();
  }

  /// Moves [resolver] to the front of the chain.
  ///
  /// This is useful when a more specific resolver should take precedence
  /// over a generic resolver.
  bool prioritize(SourceResolver resolver) {
    final index = _resolvers.indexOf(resolver);

    if (index < 0) {
      return false;
    }

    if (index == 0) {
      return true;
    }

    _resolvers
      ..removeAt(index)
      ..insert(0, resolver);
    return true;
  }

  /// Returns the first resolver that supports [source].
  SourceResolver? findResolver(PlayerSource source) {
    for (final resolver in _resolvers) {
      if (resolver.supports(source)) {
        return resolver;
      }
    }

    return null;
  }

  /// Returns all resolvers that support [source], preserving registration
  /// order.
  Iterable<SourceResolver> matchingResolvers(PlayerSource source) sync* {
    for (final resolver in _resolvers) {
      if (resolver.supports(source)) {
        yield resolver;
      }
    }
  }

  @override
  bool supports(PlayerSource source) {
    return findResolver(source) != null;
  }

  @override
  Future<ResolvedSource> resolve(PlayerSource source, {SourceResolveContext context = SourceResolveContext.empty}) {
    final resolver = findResolver(source);

    if (resolver == null) {
      // Delivered through the returned Future, as an `async` body did, so
      // no caller ever sees this failure thrown synchronously.
      return Future<ResolvedSource>.error(StateError('No source resolver supports source: ${source.uri}'));
    }

    return resolver.resolve(source, context: context);
  }
}
