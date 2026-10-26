import '../domain/transaction.dart';
import '../domain/enums.dart';
import '../services/sms/sender_registry.dart';
import '../services/sms/sms_guards.dart';

/// The ledger's admission rule: may this row affect the user's totals?
///
/// Deliberately thin. The predicates live in `SmsGuards` (text) and
/// `SenderRegistry` (identity) so the parser and the ledger cannot disagree
/// about what "money moved" means.
class TxnGuards {
  const TxnGuards({this.registry = const SenderRegistry()});

  final SenderRegistry registry;

  bool isCountable(Txn txn) {
    final body = txn.rawBody;
    // CSV imports and manual entries are typed by a human: nothing to re-derive.
    if (body == null || body.trim().isEmpty) return true;

    // A bank statement row is the bank's own record, reconciled against the
    // running balance: it has no message wording to vet.
    if (txn.sourceType == TxnSourceType.statement) return true;
    final lower = body.toLowerCase();
    // A phone-number or look-alike header never posts money, in either
    // direction: "Rs 15,000 credited to your a/c … Bal …" from a 10-digit
    // number is the seller scam (H6), however flawless the template.
    if (txn.sender != null &&
        registry.resolve(txn.sender!).trust == SenderTrust.suspicious) {
      return false;
    }
    if (SmsGuards.notMovedYet(lower)) return false;
    // A biller's receipt has no money verb ("Recharge successful"); it was
    // admitted by `SmsGuards.paidReceipt`, and the dedupe engine drops it
    // whenever a bank alert reports the same payment.
    if (txn.sourceType == TxnSourceType.receipt) return true;
    if (!SmsGuards.moneyMoved(lower)) return false;
    if (SmsGuards.merchantReceipt(lower) && !_hasBankEvidence(txn)) return false;
    if (txn.sender != null && !_hasBankEvidence(txn)) {
      final resolved = registry.resolve(txn.sender!);
      if (registry.isMerchantReceiptSender(resolved)) return false;
    }
    return true;
  }

  /// A bank alert names the account/card and usually a running balance; an
  /// order confirmation does not.
  bool _hasBankEvidence(Txn txn) {
    if (txn.cardKey != null) return true;
    if (txn.balanceAfterPaise != null) return true;
    if (txn.availableLimitPaise != null) return true;
    final body = txn.rawBody?.toLowerCase() ?? '';
    return body.contains('a/c') ||
        body.contains('avl bal') ||
        body.contains('available balance') ||
        body.contains('avl lmt');
  }
}