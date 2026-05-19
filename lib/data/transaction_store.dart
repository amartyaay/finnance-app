import '../models/transaction_models.dart';

abstract class TransactionStore {
  Future<int> upsertTransactions(
    List<ParsedTransaction> transactions, {
    required DateTime createdAt,
  });

  Future<List<FinanceTransaction>> allTransactions();

  Future<List<FinanceTransaction>> recentTransactions({int limit = 20});

  Future<List<FinanceTransaction>> uncategorizedTransactions({int limit = 10});

  Future<int> monthlySpendPaise(DateTime month);

  Future<List<ExpenseCategory>> categories();

  Future<ExpenseCategory> addCategory(String name);

  Future<void> assignCategory({
    required int transactionId,
    required ExpenseCategory category,
    required DateTime classifiedAt,
  });

  Future<DateTime?> lastScanAt();

  Future<void> saveLastScanAt(DateTime scannedAt);
}
