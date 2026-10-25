import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/demo_repository.dart';
import '../data/finance_repository.dart';
import '../data/sqlite_finance_repository.dart';
import '../domain/enums.dart';
import '../domain/inbox_store.dart';
import '../domain/merchant_rule.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../services/sms_reader.dart';

/// Single source of truth for the UI.
///
/// Owns which repository is active (real device data vs generated demo), the
/// loading/scanning flags, and the last error. Screens only read [data] and call
/// the actions below.
class AppState extends ChangeNotifier {
  AppState({
    FinanceRepository? repository,
    SmsPermissionGate? permissions,
    DateTime Function()? now,
  }) : _realRepository = repository ?? SqliteFinanceRepository(),
       _permissions = permissions ?? const PermissionHandlerGate(),
       _now = now ?? DateTime.now {
    _data = HomeData.empty(_now());
  }

  final FinanceRepository _realRepository;
  final SmsPermissionGate _permissions;
  final DateTime Function() _now;

  FinanceRepository? _demoRepository;
  late HomeData _data;
  bool _isLoading = true;
  bool _isScanning = false;
  String? _errorMessage;
  bool _hasSmsPermission = false;
  bool _demoMode = false;

  HomeData get data => _data;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  bool get isDemo => _demoMode;
  bool get hasSmsPermission => _hasSmsPermission;
  String? get errorMessage => _errorMessage;

  FinanceRepository get _active => _demoMode
      ? (_demoRepository ??= DemoFinanceRepository(now: _now()))
      : _realRepository;

  /// The stored-SMS surface, when the active source really has an inbox.
  ///
  /// Demo data and generated repositories have no `sms_messages` table, so this
  /// is null there and the optional "All messages" screen shows its explanatory
  /// empty state instead of pretending to list messages.
  InboxStore? get inboxStore {
    if (_demoMode) return null;
    final Object repository = _realRepository;
    if (repository is InboxStore) return repository;
    return null;
  }

  Future<void> init() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _hasSmsPermission = await _permissions.isGranted();
      _data = await _active.load();
      // First run with permission but nothing parsed: pull the inbox once so the
      // app is useful immediately instead of showing an empty dashboard.
      if (!_demoMode && _hasSmsPermission && _data.transactions.isEmpty) {
        await _ingestQuietly();
      }
    } catch (error) {
      _errorMessage = _friendly(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      _hasSmsPermission = await _permissions.isGranted();
      _data = await _active.load();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = _friendly(error);
    }
    notifyListeners();
  }

  Future<void> requestPermission() async {
    _hasSmsPermission = await _permissions.request();
    notifyListeners();
    if (_hasSmsPermission) {
      await scanInbox();
    }
  }

  Future<void> openSettings() async {
    await _permissions.openSettings();
    _hasSmsPermission = await _permissions.isGranted();
    notifyListeners();
  }

  Future<void> scanInbox() async {
    if (_isScanning) return;
    if (_demoMode) {
      await exitDemo();
      return;
    }
    if (!_hasSmsPermission) {
      await requestPermission();
      return;
    }

    _isScanning = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _active.ingest();
      _data = await _active.load();
    } catch (error) {
      _errorMessage = _friendly(error);
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> _ingestQuietly() async {
    try {
      await _realRepository.ingest();
      _data = await _realRepository.load();
    } catch (_) {
      // A failed first scan is not worth an error banner; the empty state
      // explains what to do next.
    }
  }

  /// Re-derives the whole ledger from the stored messages.
  ///
  /// Used after a parser upgrade (also triggered automatically when
  /// `parserVersion` changes) and available to Settings as a repair action.
  /// User category choices and learned merchant rules are preserved.
  Future<void> reparse() async {
    if (_isScanning) return;
    _isScanning = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _active.reparseAll();
      _data = await _active.load();
    } catch (error) {
      _errorMessage = _friendly(error);
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Removes a card the user says is not theirs (e.g. an account mask an older
  /// build mistook for plastic).
  Future<void> deleteCard(String issuer, String last4) async {
    await _active.deleteCard(issuer, last4);
    _data = await _active.load();
    notifyListeners();
  }

  Future<void> setCategory(
    Txn txn,
    String categoryName,
    SpendCategoryKind kind,
  ) async {
    await _active.assignCategory(
      txnKey: txn.key,
      categoryName: categoryName,
      kind: kind,
    );
    _data = await _active.load();
    notifyListeners();
  }

  /// "Not a transaction": removes the row and teaches the repository the shape
  /// of the alert so the next scan does not add it back.
  Future<void> notATransaction(Txn txn) async {
    await _active.excludeTxn(txn.key);
    _data = await _active.load();
    notifyListeners();
  }

  /// The merchant rules the user has taught, most used first (Settings).
  Future<List<MerchantRule>> merchantRules() => _active.merchantRules();

  /// Undoes a learned merchant rule. Existing rows keep their category; future
  /// scans fall back to the bundled categoriser.
  Future<void> forgetMerchantRule(String signature) async {
    await _active.forgetMerchantRule(signature);
    _data = await _active.load();
    notifyListeners();
  }

  Future<void> saveCard(CardAccount card) async {
    await _active.saveCard(card);
    _data = await _active.load();
    notifyListeners();
  }

  Future<void> dismissInsight(String id) async {
    await _active.dismissInsight(id);
    _data = await _active.load();
    notifyListeners();
  }

  Future<void> startDemo() async {
    _demoMode = true;
    _isLoading = true;
    notifyListeners();
    try {
      _data = await _active.load();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = _friendly(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> exitDemo() async {
    _demoMode = false;
    _demoRepository = null;
    _isLoading = true;
    notifyListeners();
    try {
      _data = await _realRepository.load();
    } catch (error) {
      _errorMessage = _friendly(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearAll() async {
    await _active.clearAll();
    _data = await _active.load();
    notifyListeners();
  }

  String _friendly(Object error) {
    if (error is SmsPermissionMissing) {
      return 'Allow SMS access to read bank alerts.';
    }
    if (error is UnsupportedError) {
      return 'SMS scanning works on Android only. Try demo data instead.';
    }
    return kDebugMode
        ? 'Debug: $error'
        : 'Something went wrong reading your messages. Try again.';
  }
}

class PermissionHandlerGate implements SmsPermissionGate {
  const PermissionHandlerGate();

  @override
  Future<bool> isGranted() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return Permission.sms.isGranted;
  }

  @override
  Future<bool> request() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final status = await Permission.sms.request();
    if (status.isGranted) {
      await Permission.notification.request();
    }
    return status.isGranted;
  }

  @override
  Future<void> openSettings() => openAppSettings();
}
