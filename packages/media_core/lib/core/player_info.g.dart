// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PlayerInfo _$PlayerInfoFromJson(Map<String, dynamic> json) => _PlayerInfo(
  title: json['title'] as String?,
  description: json['description'] as String?,
  author: json['author'] as String?,
  album: json['album'] as String?,
  artist: json['artist'] as String?,
  artworkUrl: json['artworkUrl'] as String?,
  thumbnailUrl: json['thumbnailUrl'] as String?,
  durationMs: (json['durationMs'] as num?)?.toInt(),
  width: (json['width'] as num?)?.toInt(),
  height: (json['height'] as num?)?.toInt(),
  frameRate: (json['frameRate'] as num?)?.toDouble(),
  videoBitrate: (json['videoBitrate'] as num?)?.toInt(),
  audioBitrate: (json['audioBitrate'] as num?)?.toInt(),
  format: json['format'] as String?,
  videoCodec: json['videoCodec'] as String?,
  audioCodec: json['audioCodec'] as String?,
  subtitleCodec: json['subtitleCodec'] as String?,
  audioLanguage: json['audioLanguage'] as String?,
  subtitleLanguage: json['subtitleLanguage'] as String?,
  metadata:
      (json['metadata'] as Map<String, dynamic>?)?.map((k, e) => MapEntry(k, e as String)) ?? const <String, String>{},
);

Map<String, dynamic> _$PlayerInfoToJson(_PlayerInfo instance) => <String, dynamic>{
  'title': instance.title,
  'description': instance.description,
  'author': instance.author,
  'album': instance.album,
  'artist': instance.artist,
  'artworkUrl': instance.artworkUrl,
  'thumbnailUrl': instance.thumbnailUrl,
  'durationMs': instance.durationMs,
  'width': instance.width,
  'height': instance.height,
  'frameRate': instance.frameRate,
  'videoBitrate': instance.videoBitrate,
  'audioBitrate': instance.audioBitrate,
  'format': instance.format,
  'videoCodec': instance.videoCodec,
  'audioCodec': instance.audioCodec,
  'subtitleCodec': instance.subtitleCodec,
  'audioLanguage': instance.audioLanguage,
  'subtitleLanguage': instance.subtitleLanguage,
  'metadata': instance.metadata,
};
