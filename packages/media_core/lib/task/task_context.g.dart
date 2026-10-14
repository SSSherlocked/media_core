// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_context.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskContext _$TaskContextFromJson(Map<String, dynamic> json) => _TaskContext(
  metadata: json['metadata'] as Map<String, dynamic>? ?? const <String, Object?>{},
  description: json['description'] as String?,
  source: json['source'] as String?,
  reason: json['reason'] as String?,
  requestId: _$JsonConverterFromJson<String, RequestId>(json['requestId'], const RequestIdJsonConverter().fromJson),
  generationId: _$JsonConverterFromJson<String, GenerationId>(
    json['generationId'],
    const GenerationIdJsonConverter().fromJson,
  ),
  sourceId: _$JsonConverterFromJson<String, SourceId>(json['sourceId'], const SourceIdJsonConverter().fromJson),
  lineId: json['lineId'] as String?,
  quality: json['quality'] as String?,
  retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
  maxRetries: (json['maxRetries'] as num?)?.toInt(),
);

Map<String, dynamic> _$TaskContextToJson(_TaskContext instance) => <String, dynamic>{
  'metadata': instance.metadata,
  'description': instance.description,
  'source': instance.source,
  'reason': instance.reason,
  'requestId': _$JsonConverterToJson<String, RequestId>(instance.requestId, const RequestIdJsonConverter().toJson),
  'generationId': _$JsonConverterToJson<String, GenerationId>(
    instance.generationId,
    const GenerationIdJsonConverter().toJson,
  ),
  'sourceId': _$JsonConverterToJson<String, SourceId>(instance.sourceId, const SourceIdJsonConverter().toJson),
  'lineId': instance.lineId,
  'quality': instance.quality,
  'retryCount': instance.retryCount,
  'maxRetries': instance.maxRetries,
};

Value? _$JsonConverterFromJson<Json, Value>(Object? json, Value? Function(Json json) fromJson) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(Value? value, Json? Function(Value value) toJson) =>
    value == null ? null : toJson(value);
