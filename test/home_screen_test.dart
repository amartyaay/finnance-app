import 'package:finnance_app/app.dart';
import 'package:finnance_app/models/transaction_models.dart';
import 'package:finnance_app/repositories/transaction_repository.dart';
import 'package:finnance_app/services/permission_service.dart';
import 'package:finnance_app/viewmodels/theme_view_model.dart';
import 'package:finnance_app/viewmodels/home_view_model.dart';
import 'package:flutter/material.dart';
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

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
        initialScreen: AppInitialScreen.home,
      ),
    );
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

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
        initialScreen: AppInitialScreen.home,
      ),
    );
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

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
        initialScreen: AppInitialScreen.home,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan inbox'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tea Shop'), findsWidgets);
    expect(find.textContaining('1 parsed'), findsOneWidget);
    expect(find.textContaining('1 new'), findsOneWidget);
    expect(find.textContaining('1 SMS read'), findsOneWidget);
  });

  testWidgets('shows detected credit card summaries after a successful scan', (
    tester,
  ) async {
    final repository = _FakeTransactionRepository(
      seedTransactions: [
        FinanceTransaction(
          id: 1,
          sourceSmsId: 'sms-1',
          sender: 'ICICIC',
          normalizedSender: 'ICICIC',
          timestampMillis: DateTime(2026, 5, 19, 9, 0).millisecondsSinceEpoch,
          amountPaise: 249900,
          direction: TransactionDirection.expense,
          instrument: TransactionInstrument.creditCard,
          accountOrCardHint: '4321',
          merchantOrPayee: 'Amazon',
          cardIssuer: 'ICICI Bank',
          cardLastDigits: '4321',
          confidence: 0.94,
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

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
        initialScreen: AppInitialScreen.home,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Detected credit cards'), findsOneWidget);
    expect(find.textContaining('ICICI Bank'), findsWidgets);
    expect(find.textContaining('xx4321'), findsWidgets);
  });

  testWidgets('shows an error banner when scan fails', (tester) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(throwOnScan: true),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
        initialScreen: AppInitialScreen.home,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Scan failed. Please try again.'), findsOneWidget);
  });

  testWidgets('renders the theme selector and can switch to dark mode', (
    tester,
  ) async {
    final themeStore = _FakeThemePreferenceStore();
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );
    final themeViewModel = ThemeViewModel(
      initialPreference: AppThemePreference.system,
      preferenceStore: themeStore,
    );

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: themeViewModel,
        initialScreen: AppInitialScreen.home,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.brightness_6_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(CheckedPopupMenuItem<AppThemePreference>).at(2),
    );
    await tester.pumpAndSettle();

    expect(themeViewModel.preference, AppThemePreference.dark);
    expect(themeStore.savedPreference, AppThemePreference.dark);
  });

  testWidgets('renders dashboard in light theme', (tester) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );
    final themeViewModel = ThemeViewModel(
      initialPreference: AppThemePreference.light,
      preferenceStore: _FakeThemePreferenceStore(
        initialPreference: AppThemePreference.light,
      ),
    );

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: themeViewModel,
        initialScreen: AppInitialScreen.home,
      ),
    );
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.brightness, Brightness.light);
    expect(find.text('No masked credit cards detected yet'), findsOneWidget);
  });

  testWidgets('renders dashboard in dark theme', (tester) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );
    final themeViewModel = ThemeViewModel(
      initialPreference: AppThemePreference.dark,
      preferenceStore: _FakeThemePreferenceStore(
        initialPreference: AppThemePreference.dark,
      ),
    );

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: themeViewModel,
        initialScreen: AppInitialScreen.home,
      ),
    );
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.brightness, Brightness.dark);
  });

  testWidgets('shows Google-only login before account UI', (tester) async {
    final viewModel = HomeViewModel(
      transactionRepository: _FakeTransactionRepository(),
      permissionService: _FakePermissionService(
        initialState: SmsPermissionState.granted,
      ),
      now: () => DateTime(2026, 5, 19, 9, 0),
    );

    await tester.pumpWidget(
      FinanceApp(
        homeViewModel: viewModel,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(
      find.text('No email/password login is available in this UI.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('This month'), findsOneWidget);
  });

  testWidgets('shows web account dashboard after Google login', (tester) async {
    await tester.pumpWidget(
      FinanceApp(
        isWebOverride: true,
        themeViewModel: ThemeViewModel(
          initialPreference: AppThemePreference.system,
          preferenceStore: _FakeThemePreferenceStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Account overview'), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('No SMS on web'), findsOneWidget);
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
      cardIssuer: transaction.cardIssuer,
      cardLastDigits: transaction.cardLastDigits,
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
  Future<List<CreditCardSummary>> creditCardSummaries(DateTime month) async {
    return _summaries();
  }

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

  List<CreditCardSummary> _summaries() {
    final byCard = <String, List<FinanceTransaction>>{};
    for (final transaction in _transactions) {
      final issuer = transaction.cardIssuer;
      final digits = transaction.cardLastDigits;
      if (issuer == null || digits == null) {
        continue;
      }
      final key = '$issuer|$digits';
      byCard.putIfAbsent(key, () => <FinanceTransaction>[]).add(transaction);
    }

    final summaries = <CreditCardSummary>[];
    for (final entry in byCard.entries) {
      final grouped = entry.value;
      grouped.sort((a, b) => a.timestampMillis.compareTo(b.timestampMillis));
      final first = grouped.first;
      final last = grouped.last;
      summaries.add(
        CreditCardSummary(
          issuer: first.cardIssuer!,
          lastDigits: first.cardLastDigits!,
          firstSeenMillis: first.timestampMillis,
          lastSeenMillis: last.timestampMillis,
          monthlySpendPaise: grouped.fold<int>(
            0,
            (total, transaction) => total + transaction.amountPaise,
          ),
          transactionCount: grouped.length,
          confidence:
              grouped
                  .map((transaction) => transaction.confidence)
                  .reduce((a, b) => a + b) /
              grouped.length,
        ),
      );
    }
    return summaries;
  }
}

class _FakeThemePreferenceStore implements ThemePreferenceStore {
  _FakeThemePreferenceStore({
    this.initialPreference = AppThemePreference.system,
  });

  AppThemePreference initialPreference;
  AppThemePreference? savedPreference;

  @override
  Future<AppThemePreference> load() async {
    return savedPreference ?? initialPreference;
  }

  @override
  Future<void> save(AppThemePreference preference) async {
    savedPreference = preference;
  }
}
