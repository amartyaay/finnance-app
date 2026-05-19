import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/sms_message_record.dart';

abstract class SmsReaderService {
  Future<List<SmsMessageRecord>> readInbox({
    int limit = 1000,
    int? sinceMillis,
  });
}

class MethodChannelSmsReaderService implements SmsReaderService {
  const MethodChannelSmsReaderService({
    this._channel = const MethodChannel('finnance_app/sms_reader'),
  });

  final MethodChannel _channel;

  @override
  Future<List<SmsMessageRecord>> readInbox({
    int limit = 1000,
    int? sinceMillis,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'SMS inbox scanning is available on Android only.',
      );
    }

    final args = <String, Object?>{'limit': limit};
    if (sinceMillis != null) {
      args['sinceMillis'] = sinceMillis;
    }
    final response = await _channel.invokeListMethod<dynamic>(
      'readInbox',
      args,
    );

    return (response ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(SmsMessageRecord.fromMap)
        .toList(growable: false);
  }
}
