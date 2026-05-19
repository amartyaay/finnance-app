class SmsMessageRecord {
  const SmsMessageRecord({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestampMillis,
  });

  factory SmsMessageRecord.fromMap(Map<dynamic, dynamic> map) {
    return SmsMessageRecord(
      id: map['id']?.toString() ?? '',
      sender: map['sender']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      timestampMillis: _readInt(map['timestampMillis']),
    );
  }

  final String id;
  final String sender;
  final String body;
  final int timestampMillis;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis);

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
