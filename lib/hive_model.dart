import 'package:hive/hive.dart';

part 'hive_model.g.dart';

@HiveType(typeId: 0)
class PdfReadingRecord extends HiveObject {
  @HiveField(0)
  final String encryptedNoteId;
  
  @HiveField(1)
  final double readedtime;
  
  @HiveField(2)
  final int readedtimeSeconds;
  
  @HiveField(3)
  final String readedDate;
  
  @HiveField(4)
  final String recordKey;

  PdfReadingRecord({
    required this.encryptedNoteId,
    required this.readedtime,
    required this.readedtimeSeconds,
    required this.readedDate,
    required this.recordKey,
  });

  Map<String, dynamic> toJson() {
    return {
      'encrypted_note_id': encryptedNoteId,
      'readedtime': readedtime,
      'readed_date': readedDate,
    };
  }
}

@HiveType(typeId: 1)
class VideoWatchingRecord extends HiveObject {
  @HiveField(0)
  late String encryptedReferencelinkId;
  
  @HiveField(1)
  late int watchedTime;
  
  @HiveField(2)
  late String watchedDate;
  
  @HiveField(3)
  late DateTime createdAt;

  VideoWatchingRecord({
    required this.encryptedReferencelinkId,
    required this.watchedTime,
    required this.watchedDate,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'encrypted_referencelink_id': encryptedReferencelinkId,
      'watched_time': watchedTime,
      'watched_date': watchedDate,
    };
  }
}