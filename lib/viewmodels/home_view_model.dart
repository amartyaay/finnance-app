import 'package:flutter/foundation.dart';

import '../models/transaction_models.dart';
import '../repositories/transaction_repository.dart';
import '../services/import_file_service.dart';
import '../services/permission_service.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required this._transactionRepository,
    required this._permissionService,
    ImportFileService? importFileService,
    DateTime Function()? now,
  }) : _importFileService =
           importFileService ?? const FilePickerImportFileService(),
       _now = now ?? DateTime.now;

  final TransactionRepositoryBase _transactionRepository;
  final SmsPermissionService _permissionService;
  final ImportFileService _importFileService;
  final DateTime Function() _now;

  SmsPermissionState _permissionState = SmsPermissionState.unknown;
  bool _isLoading = true;
  bool _isScanning = false;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _errorMessage;
  String? _exportMessage;
  String? _importMessage;
  ImportBatchPreview? _importPreview;
  ImportResult? _lastImportResult;
  ScanResult? _lastScanResult;
  DateTime? _lastScanAt;
  int _monthlySpendPaise = 0;
  List<FinanceTransaction> _recentTransactions = const [];
  List<FinanceTransaction> _uncategorizedTransactions = const [];
  List<CreditCardSummary> _creditCardSummaries = const [];
  List<ExpenseCategory> _categories = const [];

  SmsPermissionState get permissionState => _permissionState;

  bool get isLoading => _isLoading;

  bool get isScanning => _isScanning;

  bool get isExporting => _isExporting;

  bool get isImporting => _isImporting;

  String? get errorMessage => _errorMessage;

  String? get exportMessage => _exportMessage;

  String? get importMessage => _importMessage;

  ImportBatchPreview? get importPreview => _importPreview;

  ImportResult? get lastImportResult => _lastImportResult;

  ScanResult? get lastScanResult => _lastScanResult;

  DateTime? get lastScanAt => _lastScanAt;

  int get monthlySpendPaise => _monthlySpendPaise;

  List<FinanceTransaction> get recentTransactions => _recentTransactions;

  List<FinanceTransaction> get uncategorizedTransactions =>
      _uncategorizedTransactions;

  List<CreditCardSummary> get creditCardSummaries => _creditCardSummaries;

  List<ExpenseCategory> get categories => _categories;

  bool get hasSmsPermission => _permissionState == SmsPermissionState.granted;

  bool get isUnsupported => _permissionState == SmsPermissionState.unsupported;

  bool get shouldOpenSettings =>
      _permissionState == SmsPermissionState.permanentlyDenied;

  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _permissionState = await _permissionService.check();
      await _refreshSummary();
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _errorMessage = null;
    try {
      _permissionState = await _permissionService.check();
      await _refreshSummary();
    } catch (error) {
      _errorMessage = _friendlyError(error);
    }
    notifyListeners();
  }

  Future<void> requestPermissionAndScan() async {
    _errorMessage = null;
    _permissionState = await _permissionService.request();
    notifyListeners();

    if (_permissionState == SmsPermissionState.granted) {
      await scanInbox();
    }
  }

  Future<void> scanInbox() async {
    if (!hasSmsPermission) {
      await requestPermissionAndScan();
      return;
    }

    _isScanning = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _lastScanResult = await _transactionRepository.scanInbox(limit: 1000);
      await _refreshSummary();
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> classifyTransaction({
    required FinanceTransaction transaction,
    required ExpenseCategory category,
  }) async {
    final transactionId = transaction.id;
    if (transactionId == null) {
      return;
    }

    _errorMessage = null;
    try {
      await _transactionRepository.assignCategory(
        transactionId: transactionId,
        category: category,
      );
      await _refreshSummary();
    } catch (error) {
      _errorMessage = 'Could not update the category.';
    }
    notifyListeners();
  }

  Future<void> addCategoryAndClassify({
    required FinanceTransaction transaction,
    required String categoryName,
  }) async {
    final cleanedName = categoryName.trim();
    if (cleanedName.isEmpty) {
      return;
    }

    _errorMessage = null;
    try {
      final category = await _transactionRepository.addCategory(cleanedName);
      await classifyTransaction(transaction: transaction, category: category);
    } catch (error) {
      _errorMessage = 'Could not add that category.';
      notifyListeners();
    }
  }

  Future<void> exportCsv() async {
    _isExporting = true;
    _errorMessage = null;
    _exportMessage = null;
    notifyListeners();

    try {
      final exportedTo = await _transactionRepository.exportCsv();
      _exportMessage = 'CSV exported to $exportedTo';
    } catch (error) {
      _errorMessage = 'CSV export failed. Please try again.';
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<void> pickImportFile() async {
    _isImporting = true;
    _errorMessage = null;
    _importMessage = null;
    notifyListeners();

    try {
      final file = await _importFileService.pickImportFile();
      if (file == null) {
        _importMessage = 'Import cancelled.';
        return;
      }
      _importPreview = _transactionRepository.previewImport(file);
      if (_importPreview!.transactions.isEmpty) {
        _importMessage = _importPreview!.warnings.isEmpty
            ? 'No transactions found in ${_importPreview!.fileName}.'
            : _importPreview!.warnings.first;
      }
    } catch (error) {
      _errorMessage = 'Import failed. Please try another file.';
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> confirmImport() async {
    final preview = _importPreview;
    if (preview == null || preview.transactions.isEmpty) {
      return;
    }

    _isImporting = true;
    _errorMessage = null;
    _importMessage = null;
    notifyListeners();

    try {
      _lastImportResult = await _transactionRepository.confirmImport(preview);
      _importMessage =
          '${_lastImportResult!.insertedTransactions} of '
          '${_lastImportResult!.previewedTransactions} imported from '
          '${preview.fileName}.';
      _importPreview = null;
      await _refreshSummary();
    } catch (error) {
      _errorMessage = 'Could not save imported transactions.';
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  void cancelImportPreview() {
    _importPreview = null;
    _importMessage = null;
    notifyListeners();
  }

  Future<void> openSettings() async {
    await _permissionService.openSettings();
    _permissionState = await _permissionService.check();
    notifyListeners();
  }

  Future<void> _refreshSummary() async {
    final month = _now();
    final recent = await _transactionRepository.recentTransactions(limit: 20);
    final uncategorized = await _transactionRepository
        .uncategorizedTransactions(limit: 10);
    final total = await _transactionRepository.monthlySpendPaise(month);
    final cardSummaries = await _transactionRepository.creditCardSummaries(
      month,
    );
    final lastScan = await _transactionRepository.lastScanAt();
    final categories = await _transactionRepository.categories();

    _recentTransactions = recent;
    _uncategorizedTransactions = uncategorized;
    _creditCardSummaries = cardSummaries;
    _monthlySpendPaise = total;
    _lastScanAt = lastScan;
    _categories = categories;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('permission_denied')) {
      return 'SMS permission is required before scanning.';
    }
    if (text.contains('UnsupportedError')) {
      return 'SMS inbox scanning is available on Android only.';
    }
    return 'Scan failed. Please try again.';
  }
}
