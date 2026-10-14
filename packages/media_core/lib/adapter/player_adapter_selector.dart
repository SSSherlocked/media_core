import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_protocol.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Selects the best adapter registration for a media source.
///
/// [PlayerAdapterSelector] bridges the adapter registry and
/// concrete adapter creation. It scores every enabled
/// [PlayerAdapterRegistration] against a [PlayerSource] and
/// returns the best match.
///
/// Responsibilities:
///
/// - score adapters against a source
/// - honour explicit preferences
/// - expose candidate ordering
///
/// It does not:
///
/// - create adapter instances
/// - initialize adapters
/// - perform fallback at runtime
///
/// Those belong to:
///
/// - PlayerAdapterFactory
/// - PlayerAdapter
/// - PlayerKernel
final class PlayerAdapterSelector {
  /// Creates a selector reading from [registry].
  const PlayerAdapterSelector(this.registry);

  /// Registry of available adapters.
  final PlayerAdapterRegistry registry;

  /// Returns the best registration for [source], or `null` when
  /// no enabled adapter is registered.
  ///
  /// When [preferredId] names a registered and enabled adapter it
  /// wins unconditionally.
  PlayerAdapterRegistration? select(PlayerSource source, {String? preferredId}) {
    // A blank preference is no preference: it must not match whichever
    // backend happens to be consulted first.
    if (preferredId != null && preferredId.trim().isNotEmpty) {
      final preferred = registry.get(preferredId);

      if (preferred != null && preferred.enabled) {
        // A preference is not a hint: it wins without consulting scores.
        // Logged because "why is this backend playing?" is otherwise
        // unanswerable from the outside.
        MediaCoreLog.info(
          LogCategory.fallback,
          'backend selection: preferred backend "$preferredId" selected',
          fields: <String, Object?>{'uri': source.uri.toString(), 'preferred': preferredId},
        );

        return preferred;
      }

      MediaCoreLog.warning(
        LogCategory.fallback,
        'backend selection: preferred backend "$preferredId" is '
        '${preferred == null ? 'not registered' : 'disabled'} — falling back to scoring',
        fields: <String, Object?>{'uri': source.uri.toString(), 'registered': registry.ids.toList()},
      );
    }

    final candidates = candidatesFor(source);

    if (candidates.isEmpty) {
      MediaCoreLog.error(
        LogCategory.fallback,
        'backend selection: no enabled backend can handle the source',
        fields: <String, Object?>{'uri': source.uri.toString(), 'registered': registry.ids.toList()},
      );

      return null;
    }

    PlayerAdapterRegistration? best;
    // Same sentinel as [selectMedia]: a registration can score below zero
    // (negative priority, no protocol or format match), and a `-1` floor
    // here would report "no enabled backend" while candidates exist.
    var bestScore = -1 << 30;

    for (final candidate in candidates) {
      final candidateScore = score(candidate, source);
      if (candidateScore > bestScore) {
        bestScore = candidateScore;
        best = candidate;
      }
    }

    MediaCoreLog.info(
      LogCategory.fallback,
      'backend selection: ${best?.id} selected (score $bestScore)',
      fields: <String, Object?>{
        'uri': source.uri.toString(),
        'protocol': source.protocol.name,
        'format': source.format.name,
        'live': source.isLive,
        'scores': _scoreTable(candidates, source),
      },
    );

    return best;
  }

  /// Returns the best registration for [source].
  ///
  /// Throws [StateError] when no enabled adapter can play [source].
  PlayerAdapterRegistration require(PlayerSource source, {String? preferredId}) {
    final selected = select(source, preferredId: preferredId);
    if (selected == null) {
      throw StateError(
        'No enabled player adapter can handle source '
        '"${source.uri}" (protocol: ${source.protocol.name}, format: ${source.format.name}).',
      );
    }
    return selected;
  }

  /// Returns enabled registrations able to handle [source],
  /// ordered from best to worst match.
  List<PlayerAdapterRegistration> candidatesFor(PlayerSource source) {
    final capable = registry.registrations.where((registration) => registration.enabled).toList()
      ..sort((a, b) {
        final byScore = score(b, source).compareTo(score(a, source));
        if (byScore != 0) return byScore;
        return b.priority.compareTo(a.priority);
      });

    final table = capable.map((registration) => '${registration.id}:${score(registration, source)}').join(', ');

    MediaCoreLog.debug(
      LogCategory.fallback,
      'backend candidates: $table',
      fields: <String, Object?>{'uri': source.uri.toString(), 'live': source.isLive},
    );

    return capable;
  }

  /// Renders every candidate with its score breakdown.
  ///
  /// The breakdown is what turns "why this backend?" into an answer: it
  /// shows the priority each registration carries and which capability
  /// bonuses it earned, so a surprising winner is visible as a number
  /// rather than as a mystery.
  List<Map<String, Object?>> scoreTable(PlayerSource source) => _scoreTable(registry.registrations, source);

  List<Map<String, Object?>> _scoreTable(Iterable<PlayerAdapterRegistration> registrations, PlayerSource source) {
    final table = <Map<String, Object?>>[];

    for (final registration in registrations) {
      final capabilities = registration.capabilities;
      final protocolMatch = protocolMatches(capabilities, source);
      final formatMatch = formatMatches(capabilities, source);
      final liveMatch = source.isLive && capabilities.supportsLive;

      table.add(<String, Object?>{
        'id': registration.id,
        'enabled': registration.enabled,
        'priority': registration.priority,
        'protocolMatch': protocolMatch,
        'formatMatch': formatMatch,
        'liveMatch': liveMatch,
        'score': score(registration, source),
      });
    }

    table.sort((a, b) => (b['score']! as int).compareTo(a['score']! as int));

    return table;
  }

  /// Scores one registration against [source].
  ///
  /// Weights:
  ///
  /// - registration priority: as registered (tie-breaker baseline)
  /// - protocol match: +40
  /// - format match: +30
  /// - live support for live sources: +10
  int score(PlayerAdapterRegistration registration, PlayerSource source) {
    var score = registration.priority;
    final capabilities = registration.capabilities;

    if (protocolMatches(capabilities, source)) {
      score += 40;
    }

    if (formatMatches(capabilities, source)) {
      score += 30;
    }

    if (source.isLive && capabilities.supportsLive) {
      score += 10;
    }

    return score;
  }

  /// Whether [capabilities] declares support for [source]'s protocol.
  ///
  /// Both spellings count: the [SourceProtocol] name and the URI scheme.
  /// `SourceProtocol` has no value for every scheme an engine accepts
  /// (`rtmps`, `srt`, `ftp`), and a declaration that lists those schemes
  /// would otherwise never match anything.
  bool protocolMatches(PlayerAdapterCapabilities capabilities, PlayerSource source) {
    final protocol = source.protocol;

    if (protocol.isKnown && capabilities.supportsProtocol(protocol.name)) {
      return true;
    }

    final scheme = source.uri.scheme.trim().toLowerCase();

    return scheme.isNotEmpty && capabilities.supportsProtocol(scheme);
  }

  /// Whether [capabilities] declares support for [source]'s container.
  ///
  /// Both spellings count: the [SourceFormat] name and the raw URI
  /// extension. The enum and the extension disagree in places (`.ts` is
  /// [SourceFormat.mpegTs]), and containers the enum does not model at all
  /// (`rmvb`, `ape`, `nut`) can only be matched as extensions.
  bool formatMatches(PlayerAdapterCapabilities capabilities, PlayerSource source) {
    final format = source.format;

    if (format.isKnown && capabilities.supportsFormat(format.name)) {
      return true;
    }

    final extension = SourceFormat.extensionOf(source.uri);

    if (extension != null && capabilities.supportsFormat(extension)) {
      return true;
    }

    // The enum can be present while the URI has no extension (a source
    // built by hand from a manifest URL): fall back to the enum's own
    // conventional extension.
    final conventional = format.extension;

    return conventional != null && capabilities.supportsFormat(conventional);
  }

  // ---------------------------------------------------------------------------
  // MediaSource-aware selection
  //
  // The PlayerSource-based methods above predate the composite model. When
  // the caller already has a MediaSource — a Bilibili DASH pair, a
  // multi-audio source — scoring through the flat path loses the one signal
  // that decides whether the source is playable at all: the backend's
  // CompositeSupport. The methods below keep the same weighting for
  // protocol and format but add a composite bonus so a registry that
  // includes both Media3 and Fijk picks Media3 for a composite source
  // without the caller having to prefer it by id.
  // ---------------------------------------------------------------------------

  /// Returns the best registration for [source], or `null` when
  /// no enabled adapter is registered.
  ///
  /// Behaves like [select] but scores against the shape of a
  /// [MediaSource], including whether the backend's
  /// [PlayerAdapterCapabilities.compositeSupport] matches the source
  /// being composite.
  PlayerAdapterRegistration? selectMedia(MediaSource source, {String? preferredId}) {
    if (preferredId != null && preferredId.trim().isNotEmpty) {
      final preferred = registry.get(preferredId);

      if (preferred != null && preferred.enabled) {
        MediaCoreLog.info(
          LogCategory.fallback,
          'backend selection: preferred backend "$preferredId" selected for '
          '${source.type.name} source',
          fields: <String, Object?>{
            'uri': _primaryUriOf(source)?.toString(),
            'preferred': preferredId,
            'sourceType': source.type.name,
          },
        );

        return preferred;
      }

      MediaCoreLog.warning(
        LogCategory.fallback,
        'backend selection: preferred backend "$preferredId" is '
        '${preferred == null ? 'not registered' : 'disabled'} — falling back to scoring',
        fields: <String, Object?>{'uri': _primaryUriOf(source)?.toString(), 'registered': registry.ids.toList()},
      );
    }

    final candidates = mediaCandidatesFor(source);

    if (candidates.isEmpty) {
      MediaCoreLog.error(
        LogCategory.fallback,
        'backend selection: no enabled backend can handle the ${source.type.name} source',
        fields: <String, Object?>{'uri': _primaryUriOf(source)?.toString(), 'registered': registry.ids.toList()},
      );

      return null;
    }

    PlayerAdapterRegistration? best;
    var bestScore = -1 << 30;

    for (final candidate in candidates) {
      final candidateScore = scoreMedia(candidate, source);
      if (candidateScore > bestScore) {
        bestScore = candidateScore;
        best = candidate;
      }
    }

    MediaCoreLog.info(
      LogCategory.fallback,
      'backend selection: ${best?.id} selected (score $bestScore) for '
      '${source.type.name} source',
      fields: <String, Object?>{
        'uri': _primaryUriOf(source)?.toString(),
        'sourceType': source.type.name,
        'composite': source is CompositeMediaSource,
        'scores': _mediaScoreTable(candidates, source),
      },
    );

    return best;
  }

  /// Returns the best registration for [source].
  ///
  /// Throws [StateError] when no enabled adapter can play [source].
  PlayerAdapterRegistration requireMedia(MediaSource source, {String? preferredId}) {
    final selected = selectMedia(source, preferredId: preferredId);
    if (selected == null) {
      throw StateError(
        'No enabled player adapter can handle ${source.type.name} media source '
        '"${_primaryUriOf(source) ?? '<no uri>'}".',
      );
    }
    return selected;
  }

  /// Returns enabled registrations able to handle [source],
  /// ordered from best to worst match.
  List<PlayerAdapterRegistration> mediaCandidatesFor(MediaSource source) {
    final capable = registry.registrations.where((r) => r.enabled).toList()
      ..sort((a, b) {
        final byScore = scoreMedia(b, source).compareTo(scoreMedia(a, source));
        if (byScore != 0) return byScore;
        return b.priority.compareTo(a.priority);
      });

    final table = capable.map((registration) => '${registration.id}:${scoreMedia(registration, source)}').join(', ');

    MediaCoreLog.debug(
      LogCategory.fallback,
      'backend candidates (${source.type.name}): $table',
      fields: <String, Object?>{'uri': _primaryUriOf(source)?.toString()},
    );

    return capable;
  }

  /// Renders every candidate with its score breakdown against a
  /// [MediaSource].
  List<Map<String, Object?>> mediaScoreTable(MediaSource source) => _mediaScoreTable(registry.registrations, source);

  List<Map<String, Object?>> _mediaScoreTable(Iterable<PlayerAdapterRegistration> registrations, MediaSource source) {
    final primary = _primaryTrackOf(source);
    final isComposite = source is CompositeMediaSource;
    final table = <Map<String, Object?>>[];

    for (final registration in registrations) {
      final capabilities = registration.capabilities;

      table.add(<String, Object?>{
        'id': registration.id,
        'enabled': registration.enabled,
        'priority': registration.priority,
        'protocolMatch': primary != null && _protocolMatchesTrack(capabilities, primary),
        'formatMatch': primary != null && _formatMatchesTrack(capabilities, primary),
        'compositeSupport': capabilities.compositeSupport.name,
        'compositeMatch': isComposite && capabilities.supportsComposite,
        'score': scoreMedia(registration, source),
      });
    }

    table.sort((a, b) => (b['score']! as int).compareTo(a['score']! as int));

    return table;
  }

  /// Scores one registration against a [MediaSource].
  ///
  /// Weights:
  ///
  /// - registration priority: as registered (baseline)
  /// - protocol match on the primary track: +40
  /// - format match on the primary track: +30
  /// - composite support bonus when the source is composite:
  ///   [CompositeSupport.native] +60, [CompositeSupport.externalAudio]
  ///   +40, [CompositeSupport.none] no bonus — this ranks Media3 above
  ///   MPV above single-URL engines for a DASH pair without hiding the
  ///   weaker backends entirely, so a caller with only Fijk wired still
  ///   gets a registration and the planner is the one that refuses,
  ///   with a reason.
  /// - audio-only progressive source and [PlayerAdapterCapabilities.supportsAudioOnly]: +10
  /// - live source and [PlayerAdapterCapabilities.supportsLive]: +10
  int scoreMedia(PlayerAdapterRegistration registration, MediaSource source) {
    var score = registration.priority;
    final capabilities = registration.capabilities;
    final primary = _primaryTrackOf(source);

    if (primary != null) {
      if (_protocolMatchesTrack(capabilities, primary)) {
        score += 40;
      }
      if (_formatMatchesTrack(capabilities, primary)) {
        score += 30;
      }
    }

    if (source is CompositeMediaSource) {
      switch (capabilities.compositeSupport) {
        case CompositeSupport.native:
          score += 60;
        case CompositeSupport.externalAudio:
          score += 40;
        case CompositeSupport.none:
          break;
      }
    } else if (source is ProgressiveMediaSource) {
      // A progressive audio-only source is the one shape where
      // supportsAudioOnly is a selection signal at planning time;
      // composite sources carry their audio explicitly as another
      // track, so this bonus is deliberately scoped here.
      if (primary != null && primary.kind == MediaTrackType.audio && capabilities.supportsAudioOnly) {
        score += 10;
      }
    }

    // Live parity with the PlayerSource path: a backend that cannot
    // hold a live stream open should not win a live source on
    // protocol and format alone. Composite live sources get the same
    // bonus, which keeps a guaranteed planner refusal from landing on a
    // non-live engine that would fail even later.
    if (source.live && capabilities.supportsLive) {
      score += 10;
    }

    return score;
  }

  /// Whether [capabilities] can consume a composite source at all.
  ///
  /// Kept as a first-class predicate so callers outside the selector
  /// (e.g. an app that hides "Play in high quality" for composite
  /// sources on Fijk) can ask the same question without re-deriving
  /// it.
  bool compositeMatches(PlayerAdapterCapabilities capabilities, MediaSource source) {
    if (source is! CompositeMediaSource) {
      return true;
    }
    return capabilities.supportsComposite;
  }
}

Uri? _primaryUriOf(MediaSource source) => _primaryTrackOf(source)?.uri;

MediaTrack? _primaryTrackOf(MediaSource source) {
  if (source is ProgressiveMediaSource) {
    return source.track;
  }
  if (source is CompositeMediaSource) {
    return source.primaryVideo ?? source.primaryAudio;
  }
  return null;
}

bool _protocolMatchesTrack(PlayerAdapterCapabilities capabilities, MediaTrack track) {
  final protocol = track.protocol;
  if (protocol.isKnown && capabilities.supportsProtocol(protocol.name)) {
    return true;
  }
  final scheme = track.uri.scheme.trim().toLowerCase();
  return scheme.isNotEmpty && capabilities.supportsProtocol(scheme);
}

bool _formatMatchesTrack(PlayerAdapterCapabilities capabilities, MediaTrack track) {
  final format = track.format;
  if (format.isKnown && capabilities.supportsFormat(format.name)) {
    return true;
  }
  final extension = SourceFormat.extensionOf(track.uri);
  if (extension != null && capabilities.supportsFormat(extension)) {
    return true;
  }
  final conventional = format.extension;
  return conventional != null && capabilities.supportsFormat(conventional);
}
