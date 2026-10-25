import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/sms_message.dart';

/// Reads SMS from the Android inbox through a method channel.
abstract class SmsInboxReader {
  Future<List<SmsMessage>> readInbox({int limit = 2000, int? sinceMillis});
}

class ChannelSmsInboxReader implements SmsInboxReader {
  const ChannelSmsInboxReader();

  static const _channel = MethodChannel('finnance_app/sms_reader');

  @override
  Future<List<SmsMessage>> readInbox({int limit = 2000, int? sinceMillis}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('SMS scanning is available on Android only.');
    }
    final args = <String, Object?>{'limit': limit};
    if (sinceMillis != null) args['sinceMillis'] = sinceMillis;
    final response = await _channel.invokeListMethod<dynamic>('readInbox', args);
    return (response ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (map) => SmsMessage(
            id: map['id']?.toString() ?? '',
            sender: map['sender']?.toString() ?? '',
            body: map['body']?.toString() ?? '',
            receivedAtMs: _asInt(map['timestampMillis']),
          ),
        )
        .where((m) => m.id.isNotEmpty && m.body.isNotEmpty)
        .toList(growable: false);
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Permission gate for SMS access.
abstract class SmsPermissionGate {
  Future<bool> isGranted();
  Future<bool> request();
  Future<void> openSettings();
}
