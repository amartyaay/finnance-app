import 'package:finnance_app/app.dart';
import 'package:finnance_app/models/transaction_models.dart';
import 'package:finnance_app/repositories/transaction_repository.dart';
import 'package:finnance_app/services/permission_service.dart';
import 'package:finnance_app/viewmodels/home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows permission needed when SMS access is denied', (
    tester,
  ) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.denied,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );

    await tester.pumpWidget(FinanceApp(homeViewModel: viewModel));
    await tester.pumpAndSettle();

    expect(find.text('SMS access required'), findsOneWidget);
    expect(find.text('Allow SMS'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no parsed transactions', (
    tester,
  ) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );

    await tester.pumpWidget(FinanceApp(homeViewModel: viewModel));
    await tester.pumpAndSettle();

    expect(find.text('No transactions parsed yet'), findsOneWidget);
    expect(find.text('Grant SMS access to start'), findsNothing);
  });

  testWidgets('renders parsed transactions after a successful scan', (
    tester,
  ) async {
    final repository = _FakeTransactionRepository(
      seedTransactions: [
        FinanceTransaction(
          id: 1,
          sourceSmsId: 'sms-1',
          sender: 'SBIUPI',
          normalizedSender: 'SBIUPI',
          timestampMillis: DateTime(2026, 5, 19, 9, 0).millisecondsSinceEpoch,
          amountPaise: 12000,
          direction: TransactionDirection.expense,
          instrument: TransactionInstrument.upi,
          accountOrCardHint: '9988',
          merchantOrPayee: 'Tea Shop',
          confidence: 0.9,
          createdAtMillis: DateTime(2026, 5, 19, 9, 0).millisecondsSinceEpoch,
        ),
      ],
    );
    final viewModel = HomeViewModel(
      transactionRepository: repository,
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );

    await tester.pumpWidget(FinanceApp(homeViewModel: viewModel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan inbox'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tea Shop'), findsWidgets);
    expect(find.textContaining('1 parsed'), findsOneWidget);
    expect(find.textContaining('1 new'), findsOneWidget);
    expect(find.textContaining('1 SMS read'), findsOneWidget);
  });

  testWidgets('shows an error banner when scan fails', (tester) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(throwOnScan: true),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );

    await tester.pumpWidget(FinanceApp(homeViewModel: viewModel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Scan failed. Please try again.'), findsOneWidget);
  });
}

class _FakePermissionService implements SmsPermissionService {
  _FakePermissionService({required SmsPermissionState initialState})
    : _state = initialState;

  SmsPermissionState _state;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<SmsPermissionState> check() async => _state;

  @override
  Future<SmsPermissionState> request() async {
    _state = SmsPermissionState.granted;
    return _state;
  }
}

class _FakeTransactionRepository implements TransactionRepositoryBase {
  _FakeTransactionRepository({
    this.seedTransactions = const [],
    this.throwOnScan = false,
  });

  final bool throwOnScan;
  final List<FinanceTransaction> seedTransactions;
  final List<FinanceTransaction> _transactions = [];
  final List<ExpenseCategory> _categories = [
    const ExpenseCategory(
      id: 1,
      name: 'Food',
      isDefault: true,
      createdAtMillis: 0,
    ),
    const ExpenseCategory(
      id: 2,
      name: 'Travel',
      isDefault: true,
      createdAtMillis: 0,
    ),
    const ExpenseCategory(
      id: 3,
      name: 'Lifestyle',
      isDefault: true,
      createdAtMillis: 0,
    ),
  ];
  DateTime? _lastScanAt;

  @override
  Future<ExpenseCategory> addCategory(String name) async {
    final category = ExpenseCategory(
      id: _categories.length + 1,
      name: name,
      isDefault: false,
      createdAtMillis: 0,
    );
    _categories.add(category);
    return category;
  }

  @override
  Future<void> assignCategory({
    required int transactionId,
    required ExpenseCategory category,
  }) async {
    final index = _transactions.indexWhere(
      (transaction) => transaction.id == transactionId,
    );
    if (index < 0) {
      return;
    }
    final transaction = _transactions[index];
    _transactions[index] = FinanceTransaction(
      id: transaction.id,
      sourceSmsId: transaction.sourceSmsId,
      sender: transaction.sender,
      normalizedSender: transaction.normalizedSender,
      timestampMillis: transaction.timestampMillis,
      amountPaise: transaction.amountPaise,
      direction: transaction.direction,
      instrument: transaction.instrument,
      accountOrCardHint: transaction.accountOrCardHint,
      merchantOrPayee: transaction.merchantOrPayee,
      referenceId: transaction.referenceId,
      confidence: transaction.confidence,
      categoryId: category.id,
      categoryName: category.name,
      classifiedAtMillis: DateTime(2026, 5, 19).millisecondsSinceEpoch,
      createdAtMillis: transaction.createdAtMillis,
    );
  }

  @override
  Future<List<ExpenseCategory>> categories() async => _categories;

  @override
  Future<String> exportCsv() async => 'finance-transactions.csv';

  @override
  Future<int> monthlySpendPaise(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _transactions
        .where(
          (transaction) =>
              transaction.direction == TransactionDirection.expense &&
              !transaction.timestamp.isBefore(start) &&
              transaction.timestamp.isBefore(end),
        )
        .fold<int>(0, (total, transaction) => total + transaction.amountPaise);
  }

  @override
  Future<DateTime?> lastScanAt() async => _lastScanAt;

  @override
  Future<List<FinanceTransaction>> recentTransactions({int limit = 20}) async {
    final transactions = _transactions.toList()
      ..sort((a, b) => b.timestampMillis.compareTo(a.timestampMillis));
    return transactions.take(limit).toList(growable: false);
  }

  @override
  Future<List<FinanceTransaction>> uncategorizedTransactions({
    int limit = 10,
  }) async {
    return _transactions
        .where(
          (transaction) =>
              transaction.categoryId == null &&
              transaction.direction == TransactionDirection.expense,
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<ScanResult> scanInbox({int limit = 1000, int? sinceMillis}) async {
    if (throwOnScan) {
      throw StateError('scan failed');
    }
    if (_transactions.isEmpty) {
      _transactions.addAll(seedTransactions);
    }
    _lastScanAt = DateTime(2026, 5, 19, 9, 0);
    return ScanResult(
      totalSmsRead: seedTransactions.length,
      parsedTransactions: seedTransactions.length,
      insertedTransactions: seedTransactions.length,
      scannedAt: _lastScanAt!,
    );
  }
}
