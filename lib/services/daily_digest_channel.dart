import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Schedules and posts the 10 pm summary on the Android side.
abstract class DigestScheduler {
  /// Arms (or cancels) the daily 10 pm alarm.
  Future<void> schedule({required bool enabled});

  /// Shows a summary notification now.
  Future<void> post(String title, String body);

  /// Runs the real 10 pm job now. False when there is no platform side.
  Future<bool> runNow();
}

/// The platform channel `MainActivity` and `DailyDigestReceiver` answer.
class ChannelDigestScheduler implements DigestScheduler {
  const ChannelDigestScheduler();

  static const channel = MethodChannel('finnance_app/digest');

  @override
  Future<void> schedule({required bool enabled}) async {
    try {
      await channel.invokeMethod<void>('schedule', {'enabled': enabled});
    } on Object catch (error) {
      // Host tests and other platforms have no alarm to arm.
      debugPrint('digest schedule unavailable: $error');
    }
  }

  @override
  Future<bool> runNow() async {
    try {
      await channel.invokeMethod<void>('runNow');
      return true;
    } on Object catch (error) {
      debugPrint('digest runNow unavailable: $error');
      return false;
    }
  }

  @override
  Future<void> post(String title, String body) async {
    try {
      await channel.invokeMethod<void>('post', {'title': title, 'body': body});
    } on Object catch (error) {
      debugPrint('digest post unavailable: $error');
    }
  }
}
