import '../domain/enums.dart';
import '../domain/merchant_rule.dart';
import '../domain/merchant_signature.dart';
import '../domain/transaction.dart';
import '../services/sms/sender_registry.dart';

/// Bridges transactions and the two kinds of learned rule.
///
/// Kept pure so the same matching runs in the SQLite repository, the demo
/// repository and the tests: a rule learned in one place must behave exactly
/// the same in the others.
class MerchantLearning {
  const MerchantLearning({this.registry = const SenderRegistry()});

  final SenderRegistry registry;

  /// Key for the row's merchant, falling back to the sender entity.
  String? signatureFor(Txn txn) => MerchantSignature.of(
    txn.merchant,
    senderEntity: senderEntityFor(txn.sender),
  );

  /// Display name of the bank/entity that sent the alert, when resolvable.
  String? senderEntityFor(String? sender) {
    if (sender == null || sender.trim().isEmpty) return null;
    return registry.resolve(sender).entity;
  }

  /// Key for the "never count this again" rule.
  String exclusionFor(Txn txn) => MerchantSignature.exclusion(
    sender: txn.sender,
    merchant: txn.merchant,
    amountPaise: txn.amountPaise,
  );

  /// The rule that should categorise [txn], if any.
  ///
  /// A merchant-keyed rule may rewrite any kind: the user made that choice on a
  /// row they could see. A **sender-keyed** rule (the row had no merchant, so
  /// the key is just `hdfc bank`) is only trusted for spends — otherwise one
  /// anonymous spend would relabel every salary credit from that bank.
  MerchantRule? match(Map<String, MerchantRule> rules, Txn txn) {
    if (rules.isEmpty) return null;
    final signature = signatureFor(txn);
    if (signature == null) return null;
    if (MerchantSignature.isSenderFallback(txn.merchant) &&
        txn.kind != TxnKind.spend) {
      return null;
    }
    return rules[signature];
  }

  /// True when the stored [row] should be re-categorised by [signature].
  ///
  /// A user's own choice is never overwritten by a later rule.
  bool matchesSignature(Txn row, String signature) {
    if (row.categorySource == CategorySource.user) return false;
    if (MerchantSignature.isSenderFallback(row.merchant) &&
        row.kind != TxnKind.spend) {
      return false;
    }
    return signatureFor(row) == signature;
  }

  /// Whether a user's choice on [txn] is informative enough to become a rule.
  ///
  /// An anonymous spend can only be keyed by the sender entity, which covers
  /// every alert from that bank. Writing that rule for "Other" would erase
  /// future categories rather than teach anything, so it is skipped.
  bool shouldLearn(Txn txn, SpendCategoryKind kind) {
    final signature = signatureFor(txn);
    if (signature == null) return false;
    if (MerchantSignature.isSenderFallback(txn.merchant)) {
      return txn.kind == TxnKind.spend && kind != SpendCategoryKind.other;
    }
    return true;
  }
}
