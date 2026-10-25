import 'enums.dart';
import 'sms_inbox.dart';

/// The small data surface the "All messages" screen needs.
///
/// It is a separate interface from [FinanceRepository] so the inbox can be
/// backed by the SQLite store without forcing every repository (demo, fakes in
/// tests) to grow message-paging methods it can never answer. [AppState]
/// exposes it only when the active source really has stored SMS.
abstract interface class InboxStore {
  /// Newest first, paged. [filter] is one of [InboxFilter.slug]; [query]
  /// matches the message body or the sender.
  Future<List<SmsMessageRow>> recentMessages({
    int offset = 0,
    int limit = 50,
    String? filter,
    String? query,
  });

  /// Counts across every stored message, independent of paging/filtering.
  Future<InboxStats> inboxStats();

  /// Negative-rule keys already remembered ("this alert shape is not a
  /// transaction"), so the screen can show those rows as not counted.
  Future<Set<String>> excludedShapes();

  /// Applies [categoryName] to every stored transaction matching [signature]
  /// and remembers the choice as a merchant rule for future ingests.
  ///
  /// Returns how many existing transactions were updated.
  Future<int> applyCategoryToSignature({
    required String signature,
    required String categoryName,
    required SpendCategoryKind kind,
  });

  /// Categorises exactly one transaction and learns nothing. Backs the
  /// "Just this payment" scope.
  Future<void> assignCategoryOnce({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  });

  /// Excludes a message (and, when [everyFromMerchant], every transaction with
  /// [signature]) from the ledger. The exclusion is remembered so future
  /// ingests do not book the same merchant again.
  ///
  /// Returns how many stored transactions were removed.
  Future<int> markNotTransaction({
    required String? signature,
    required String messageId,
    required String? txnKey,
    required bool everyFromMerchant,
  });

  /// Creates a ledger row for a message the parser did not count, using the
  /// amount and merchant the owner typed. When [rememberMerchant] is true the
  /// category is also applied to matching transactions and saved as a rule.
  Future<void> createTransactionFromMessage({
    required SmsMessageRow message,
    required int amountPaise,
    required String merchant,
    required String categoryName,
    required SpendCategoryKind kind,
    required bool rememberMerchant,
    required String? signature,
  });
}
