import 'package:json_annotation/json_annotation.dart';
import 'package:media_core/operation/operation_context.dart';
import 'package:media_core/task/task_id.dart';
import 'package:media_core/task/task_priority.dart';
import 'package:media_core/task/task_state.dart';
import 'package:media_core/task/task_type.dart';

/// Converts [TaskId] to and from its string form for JSON generation.
class TaskIdJsonConverter extends JsonConverter<TaskId, String> {
  /// Creates the task ID converter.
  const TaskIdJsonConverter();

  @override
  TaskId fromJson(String json) => TaskId.fromJson(json);

  @override
  String toJson(TaskId object) => object.toJson();
}

/// Converts [TaskType] to and from its stable string value for JSON generation.
class TaskTypeJsonConverter extends JsonConverter<TaskType, String> {
  /// Creates the task type converter.
  const TaskTypeJsonConverter();

  @override
  TaskType fromJson(String json) => TaskType.fromJson(json);

  @override
  String toJson(TaskType object) => object.toJson();
}

/// Converts [TaskState] to and from its stable string value for JSON generation.
class TaskStateJsonConverter extends JsonConverter<TaskState, String> {
  /// Creates the task state converter.
  const TaskStateJsonConverter();

  @override
  TaskState fromJson(String json) => TaskState.fromJson(json);

  @override
  String toJson(TaskState object) => object.toJson();
}

/// Converts [TaskPriority] to and from its numeric level for JSON generation.
class TaskPriorityJsonConverter extends JsonConverter<TaskPriority, int> {
  /// Creates the task priority converter.
  const TaskPriorityJsonConverter();

  @override
  TaskPriority fromJson(int json) => TaskPriority.fromJson(json);

  @override
  int toJson(TaskPriority object) => object.toJson();
}

/// Converts [OperationContext] to and from its JSON map for generated code.
class OperationContextJsonConverter extends JsonConverter<OperationContext, Map<String, dynamic>> {
  /// Creates the operation context converter.
  const OperationContextJsonConverter();

  @override
  OperationContext fromJson(Map<String, dynamic> json) {
    return OperationContext.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(OperationContext object) {
    return object.toJson();
  }
}
