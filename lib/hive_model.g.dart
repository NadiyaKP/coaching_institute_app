// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PdfReadingRecordAdapter extends TypeAdapter<PdfReadingRecord> {
  @override
  final int typeId = 0;

  @override
  PdfReadingRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PdfReadingRecord(
      encryptedNoteId: fields[0] as String,
      readedtime: fields[1] as double,
      readedtimeSeconds: fields[2] as int,
      readedDate: fields[3] as String,
      recordKey: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, PdfReadingRecord obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.encryptedNoteId)
      ..writeByte(1)
      ..write(obj.readedtime)
      ..writeByte(2)
      ..write(obj.readedtimeSeconds)
      ..writeByte(3)
      ..write(obj.readedDate)
      ..writeByte(4)
      ..write(obj.recordKey);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfReadingRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VideoWatchingRecordAdapter extends TypeAdapter<VideoWatchingRecord> {
  @override
  final int typeId = 1;

  @override
  VideoWatchingRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoWatchingRecord(
      encryptedReferencelinkId: fields[0] as String,
      watchedTime: fields[1] as int,
      watchedDate: fields[2] as String,
      createdAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, VideoWatchingRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.encryptedReferencelinkId)
      ..writeByte(1)
      ..write(obj.watchedTime)
      ..writeByte(2)
      ..write(obj.watchedDate)
      ..writeByte(3)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoWatchingRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
