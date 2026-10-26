/// The on-device second opinion: a logistic regression over hashed words.
///
/// Trained once on the hand-labelled real inbox (tool/train_sms_model.py),
/// shipped as `assets/models/sms_lr.json`, evaluated here in pure Dart — no
/// network, no native runtime, ~0.1 ms per SMS, $0 a year
/// (docs/research/08-classifier-budget.md).
///
/// It never decides on its own. The rule engine is the gate; where the two
/// disagree confidently the row goes to the review queue, so a promo the rules
/// let through, or a debit the rules missed, is put in front of the user.
///
/// The featuriser must match the Python one exactly (see the trainer's
/// docstring); tool/check_sms_model_parity.dart verifies it on real messages.
library;

import 'dart:convert';
import 'dart:math' as math;

enum SmsModelClass {
  debit,
  credit,
  otp,
  promo,
  info;

  bool get movesMoney => this == debit || this == credit;
}

class SmsModelPrediction {
  const SmsModelPrediction(this.probabilities);

  /// One probability per [SmsModelClass], in enum order.
  final List<double> probabilities;

  SmsModelClass get best {
    var index = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[index]) index = i;
    }
    return SmsModelClass.values[index];
  }

  double get confidence => probabilities[best.index];

  /// Probability that money moved (debit or credit).
  double get money =>
      probabilities[SmsModelClass.debit.index] +
      probabilities[SmsModelClass.credit.index];
}

class SmsModel {
  SmsModel._(this._dim, this._bias, this._weights);

  factory SmsModel.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final classes = (json['classes'] as List).cast<String>();
    if (classes.join(',') != SmsModelClass.values.map((c) => c.name).join(',')) {
      throw const FormatException('SMS model classes do not match the app');
    }
    final weights = <int, List<double>>{};
    (json['weights'] as Map<String, dynamic>).forEach((key, value) {
      weights[int.parse(key)] = [
        for (final v in value as List) (v as num).toDouble(),
      ];
    });
    return SmsModel._(
      json['dim'] as int,
      [for (final v in json['bias'] as List) (v as num).toDouble()],
      weights,
    );
  }

  /// The bundled model's asset path.
  static const String assetPath = 'assets/models/sms_lr.json';

  final int _dim;
  final List<double> _bias;
  final Map<int, List<double>> _weights;

  static final RegExp _url = RegExp(r'https?://\S+|www\.\S+');
  static final RegExp _digits = RegExp(r'[0-9]+');
  static final RegExp _token = RegExp(r'[a-z_0]+|₹');

  /// The feature strings, exactly as the trainer builds them.
  static List<String> features(String sender, String body) {
    var text = body.toLowerCase().replaceAll(_url, ' __url__ ');
    text = text.replaceAll(_digits, '0');
    final tokens = [for (final m in _token.allMatches(text)) m.group(0)!];
    return [
      for (final t in tokens) 'w:$t',
      for (var i = 0; i + 1 < tokens.length; i++) 'b:${tokens[i]} ${tokens[i + 1]}',
      'dlt:${dltCategory(sender)}',
    ];
  }

  static String dltCategory(String sender) {
    final parts = sender.split('-');
    if (parts.length >= 3 && parts.last.length == 1) return parts.last.toUpperCase();
    return 'none';
  }

  /// 32-bit FNV-1a over UTF-8 bytes, masked every step. The product stays
  /// below 2^57, exact in the VM's 64-bit ints (the app is Android-only).
  static int fnv1a32(String text) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  SmsModelPrediction predict(String sender, String body) {
    final active = <int>{
      for (final f in features(sender, body)) fnv1a32(f) % _dim,
    };
    final scores = [..._bias];
    for (final index in active) {
      final w = _weights[index];
      if (w == null) continue;
      for (var c = 0; c < scores.length; c++) {
        scores[c] += w[c];
      }
    }
    final top = scores.reduce(math.max);
    final exps = [for (final s in scores) math.exp(s - top)];
    final total = exps.reduce((a, b) => a + b);
    return SmsModelPrediction([for (final e in exps) e / total]);
  }
}
