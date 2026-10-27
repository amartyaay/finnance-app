import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/sms_message.dart';
import '../../domain/transaction.dart';
import '../../engine/txn_guards.dart';
import '../categorizer.dart';
import 'sender_registry.dart';
import 'sms_classifier.dart';
import 'transaction_extractor.dart';

/// The "Spent ₹X" notification posted when an SMS arrives, decided by the
/// same classifier and ledger guards as the app (the Android receiver used to
/// run a second, looser parser that took "Rs.500 benefits" for a spend).
class SmsAlert {
  const SmsAlert({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  /// Null unless [message] is a completed spend the ledger would count.
  static SmsAlert? decide(
    SmsMessage message, {
    SmsClassifier? classifier,
    TransactionExtractor? extractor,
  }) {
    const registry = SenderRegistry();
    final sender = registry.resolve(message.sender);
    // A `-P` header is promotional by DLT rule: never a transaction.
    if (sender.dltCategory == 'P') return null;
    final assessment = (classifier ?? SmsClassifier()).assess(message);
    if (!assessment.isTransaction) return null;
    final txn = (extractor ?? TransactionExtractor()).extract(message, sender);
    if (txn == null || txn.kind != TxnKind.spend) return null;
    // A merchant's own receipt repeats the bank's alert for the same payment.
    if (txn.sourceType == TxnSourceType.receipt) return null;
    if (!const TxnGuards().isCountable(txn)) return null;

    final category = const Categorizer().categorize(
      txn.merchant,
      kind: txn.kind,
      transferReason: txn.transferReason,
    );
    final merchant = txn.merchant?.trim();
    final parts = [
      if (merchant != null && merchant.isNotEmpty) merchant,
      if (category.kind != SpendCategoryKind.other) category.name,
    ];
    return SmsAlert(
      title: 'Spent ${inr(txn.amount)}',
      subtitle: parts.isEmpty ? null : parts.join(' · '),
    );
  }
}
