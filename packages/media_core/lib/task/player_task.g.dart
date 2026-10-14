// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PlayerTask _$PlayerTaskFromJson(Map<String, dynamic> json) => _PlayerTask(
  id: const TaskIdJsonConverter().fromJson(json['id'] as String),
  type: const TaskTypeJsonConverter().fromJson(json['type'] as String),
  state: json['state'] == null ? TaskState.created : const TaskStateJsonConverter().fromJson(json['state'] as String),
  priority: json['priority'] == null
      ? TaskPriority.normal
      : const TaskPriorityJsonConverter().fromJson((json['priority'] as num).toInt()),
  context: json['context'] == null ? null : TaskContext.fromJson(json['context'] as Map<String, dynamic>),
  operationContext: _$JsonConverterFromJson<Map<String, dynamic>, OperationContext>(
    json['operationContext'],
    const OperationContextJsonConverter().fromJson,
  ),
  playerId: _$JsonConverterFromJson<String, PlayerId>(json['playerId'], const PlayerIdJsonConverter().fromJson),
  requestId: _$JsonConverterFromJson<String, RequestId>(json['requestId'], const RequestIdJsonConverter().fromJson),
  generationId: _$JsonConverterFromJson<String, GenerationId>(
    json['generationId'],
    const GenerationIdJsonConverter().fromJson,
  ),
  createdAt: json['createdAt'] == null ? null : DateTime.parse(json['createdAt'] as String),
  queuedAt: json['queuedAt'] == null ? null : DateTime.parse(json['queuedAt'] as String),
  startedAt: json['startedAt'] == null ? null : DateTime.parse(json['startedAt'] as String),
  completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
  error: json['error'],
  result: json['result'],
);

Map<String, dynamic> _$PlayerTaskToJson(_PlayerTask instance) => <String, dynamic>{
  'id': const TaskIdJsonConverter().toJson(instance.id),
  'type': const TaskTypeJsonConverter().toJson(instance.type),
  'state': const TaskStateJsonConverter().toJson(instance.state),
  'priority': const TaskPriorityJsonConverter().toJson(instance.priority),
  'context': instance.context,
  'operationContext': _$JsonConverterToJson<Map<String, dynamic>, OperationContext>(
    instance.operationContext,
    const OperationContextJsonConverter().toJson,
  ),
  'playerId': _$JsonConverterToJson<String, PlayerId>(instance.playerId, const PlayerIdJsonConverter().toJson),
  'requestId': _$JsonConverterToJson<String, RequestId>(instance.requestId, const RequestIdJsonConverter().toJson),
  'generationId': _$JsonConverterToJson<String, GenerationId>(
    instance.generationId,
    const GenerationIdJsonConverter().toJson,
  ),
  'createdAt': instance.createdAt?.toIso8601String(),
  'queuedAt': instance.queuedAt?.toIso8601String(),
  'startedAt': instance.startedAt?.toIso8601String(),
  'completedAt': instance.completedAt?.toIso8601String(),
  'error': instance.error,
  'result': instance.result,
};

Value? _$JsonConverterFromJson<Json, Value>(Object? json, Value? Function(Json json) fromJson) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(Value? value, Json? Function(Value value) toJson) =>
    value == null ? null : toJson(value);
