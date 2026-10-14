import 'package:json_annotation/json_annotation.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/identity/source_id.dart';

/// Reads and writes a [PlayerId] as the plain string it wraps, so
/// `json_serializable` models can hold a typed id without hand-written
/// parsing in every field.
class PlayerIdJsonConverter extends JsonConverter<PlayerId, String> {
  /// Creates the converter.
  const PlayerIdJsonConverter();

  @override
  PlayerId fromJson(String json) => PlayerId.fromJson(json);

  @override
  String toJson(PlayerId object) => object.toJson();
}

/// Reads and writes a [SessionId] as the plain string it wraps.
class SessionIdJsonConverter extends JsonConverter<SessionId, String> {
  /// Creates the converter.
  const SessionIdJsonConverter();

  @override
  SessionId fromJson(String json) => SessionId.fromJson(json);

  @override
  String toJson(SessionId object) => object.toJson();
}

/// Reads and writes a [SlotId] as the plain string it wraps.
class SlotIdJsonConverter extends JsonConverter<SlotId, String> {
  /// Creates the converter.
  const SlotIdJsonConverter();

  @override
  SlotId fromJson(String json) => SlotId.fromJson(json);

  @override
  String toJson(SlotId object) => object.toJson();
}

/// Reads and writes a [SourceId] as the plain string it wraps.
class SourceIdJsonConverter extends JsonConverter<SourceId, String> {
  /// Creates the converter.
  const SourceIdJsonConverter();

  @override
  SourceId fromJson(String json) => SourceId.fromJson(json);

  @override
  String toJson(SourceId object) => object.toJson();
}

/// Reads and writes an [OperationId] as the plain string it wraps.
class OperationIdJsonConverter extends JsonConverter<OperationId, String> {
  /// Creates the converter.
  const OperationIdJsonConverter();

  @override
  OperationId fromJson(String json) => OperationId.fromJson(json);

  @override
  String toJson(OperationId object) => object.toJson();
}

/// Reads and writes a [RequestId] as the plain string it wraps.
class RequestIdJsonConverter extends JsonConverter<RequestId, String> {
  /// Creates the converter.
  const RequestIdJsonConverter();

  @override
  RequestId fromJson(String json) => RequestId.fromJson(json);

  @override
  String toJson(RequestId object) => object.toJson();
}

/// Reads and writes a [GenerationId] as the plain string it wraps.
class GenerationIdJsonConverter extends JsonConverter<GenerationId, String> {
  /// Creates the converter.
  const GenerationIdJsonConverter();

  @override
  GenerationId fromJson(String json) => GenerationId.fromJson(json);

  @override
  String toJson(GenerationId object) => object.toJson();
}
