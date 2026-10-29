import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gemini Nano's state on this phone, as AICore reports it.
enum NanoStatus {
  available,
  downloadable,
  downloading,

  /// Not supported on this device (or AICore has no config for it yet).
  unavailable;

  String get label => switch (this) {
    available => 'Ready on this phone',
    downloadable => 'Supported; the model needs to be downloaded once',
    downloading => 'Downloading the model',
    unavailable => 'Not available on this phone',
  };
}

/// What Gemini Nano says an SMS is.
enum NanoVerdict { spent, received, nothing, unsure }

/// Gemini Nano through Android AICore (ML Kit GenAI Prompt API), used as an
/// optional, user-started second opinion on messages the parser was unsure
/// about. AICore only runs while the app is on screen, so it is never part of
/// the SMS receiver or the 10 pm summary. Nothing leaves the phone.
class GeminiNano {
  const GeminiNano();

  static const _channel = MethodChannel('finnance_app/nano');

  Future<({NanoStatus status, String? error})> status() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('status');
      final raw = map?['status'] as String? ?? 'unavailable';
      return (
        status: NanoStatus.values.firstWhere(
          (s) => s.name == raw,
          orElse: () => NanoStatus.unavailable,
        ),
        error: map?['error'] as String?,
      );
    } on Object catch (error) {
      return (status: NanoStatus.unavailable, error: '$error');
    }
  }

  Future<bool> download() async {
    try {
      return await _channel.invokeMethod<bool>('download') ?? false;
    } on Object catch (error) {
      debugPrint('nano download failed: $error');
      return false;
    }
  }

  Future<NanoVerdict> classify(String sender, String body) async {
    try {
      final answer = await _channel.invokeMethod<String>('prompt', {
        'text': prompt(sender, body),
        'maxTokens': 4,
      });
      return parse(answer ?? '');
    } on Object catch (error) {
      debugPrint('nano classify failed: $error');
      return NanoVerdict.unsure;
    }
  }

  /// Short, closed-label prompt: a one-word answer is cheap on a phone and
  /// easy to read back reliably.
  @visibleForTesting
  static String prompt(String sender, String body) =>
      'You read SMS sent to a person in India by banks, UPI apps, card '
      'issuers and shops. Reply with exactly one word.\n'
      'SPENT: money has left their bank account, card or wallet (a completed '
      'payment, purchase, transfer out, bill payment or SIP).\n'
      'RECEIVED: money has come into their account (a completed credit, '
      'refund or salary).\n'
      'NOTHING: anything else: offers, cashback or reward promotions, loan or '
      'credit-limit offers, OTPs, bill or due-date reminders, statements, '
      'failed, declined or pending payments.\n\n'
      'Sender: $sender\nSMS: """$body"""\nAnswer:';

  @visibleForTesting
  static NanoVerdict parse(String answer) {
    final word = answer.trim().toUpperCase();
    if (word.startsWith('SPENT')) return NanoVerdict.spent;
    if (word.startsWith('RECEIVED')) return NanoVerdict.received;
    if (word.startsWith('NOTHING')) return NanoVerdict.nothing;
    return NanoVerdict.unsure;
  }
}
