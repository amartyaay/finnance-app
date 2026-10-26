import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../data/statement_store.dart';
import '../domain/enums.dart';
import '../domain/statement.dart';
import '../services/statement/pdf_words.dart';
import '../services/statement/statement_importer.dart';
import '../services/statement/statement_words.dart';

/// A parsed file waiting for the user's "Import".
class StatementPreview {
  const StatementPreview({
    required this.statement,
    required this.fileHash,
    required this.fileName,
    required this.analysis,
    this.layout = '',
  });

  final BankStatement statement;

  /// What the reader saw, with no amounts or narration
  /// ([StatementTableBuilder.layoutReport]); shown when no rows were found.
  final String layout;
  final String fileHash;
  final String fileName;

  /// Salary and cycles of this file alone, for the review sheet.
  final StatementAnalysis analysis;
}

typedef WordReader =
    Future<List<PdfWord>> Function(String path, {String? password});

/// The bank-statement feature's state: imported accounts, the selected
/// account's rows, its salary verdict and salary-to-salary cycles.
///
/// Fully on-device. The password is passed straight to the PDF engine for one
/// open and is never stored; the picked file's cached copy is deleted after
/// parsing.
class StatementsController extends ChangeNotifier {
  StatementsController({
    StatementStore? store,
    StatementImporter importer = const StatementImporter(),
    WordReader? readWords,
  }) : _store = store ?? StatementStore(),
       _importer = importer,
       _readWords = readWords ?? readPdfWords;

  final StatementStore _store;
  final StatementImporter _importer;
  final WordReader _readWords;

  List<StatementAccount> _accounts = const [];
  String? _selected;
  List<StatementRow> _rows = const [];
  StatementAnalysis? _analysis;
  bool _loading = false;
  bool _loaded = false;

  List<StatementAccount> get accounts => _accounts;
  StatementAccount? get selected =>
      _accounts.where((a) => a.accountKey == _selected).firstOrNull;
  List<StatementRow> get rows => _rows;
  StatementAnalysis? get analysis => _analysis;
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;

  /// Why the last load failed (the statements screen shows it); null when ok.
  String? get loadError => _loadError;
  String? _loadError;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _accounts = await _store.accounts();
      if (_selected == null || selected == null) {
        _selected = _accounts.isEmpty ? null : _accounts.first.accountKey;
      }
      await _loadRows();
      _loadError = null;
    } catch (error) {
      // A storage failure must not take the rest of the app down with it.
      _accounts = const [];
      _rows = const [];
      _analysis = null;
      _loadError = 'Imported statements could not be read on this phone.';
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> select(String accountKey) async {
    _selected = accountKey;
    await _loadRows();
    notifyListeners();
  }

  Future<void> _loadRows() async {
    final key = _selected;
    if (key == null) {
      _rows = const [];
      _analysis = null;
      return;
    }
    _rows = await _store.rows(key);
    _analysis = _importer.analyse(_rows);
  }

  /// Opens the system document picker (no storage permission needed).
  /// Returns the cached path, or null when the user cancels.
  Future<({String path, String name})?> pickPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = file?.path;
    if (file == null || path == null) return null;
    return (path: path, name: file.name);
  }

  /// Reads and parses a picked file. Throws [PdfNeedsPassword] /
  /// [PdfWrongPassword] / [PdfUnreadable] for the screen to handle.
  Future<StatementPreview> preview(
    String path,
    String name, {
    String? password,
  }) async {
    final bytes = await File(path).readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final words = await _readWords(path, password: password);
    final statement = _importer.parse(words);
    final analysis = _importer.analyse(
      statement.rows,
      from: statement.periodFrom,
      to: statement.periodTo,
    );
    return StatementPreview(
      statement: statement,
      fileHash: hash,
      fileName: name,
      analysis: analysis,
      layout: statement.rows.isEmpty ? _importer.table.layoutReport(words) : '',
    );
  }

  Future<StatementImportResult> commit(StatementPreview preview) async {
    final result = await _store.save(
      preview.statement,
      fileHash: preview.fileHash,
    );
    _selected = preview.statement.accountKey;
    await load();
    return result;
  }

  /// The picked file is the user's bank statement: never leave a copy behind.
  Future<void> discardPickedFiles() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // Nothing cached (or not supported on this platform).
    }
  }

  Future<void> setSalary(StatementRow row, bool? isSalary) async {
    final key = row.key;
    if (key == null) return;
    await _store.setSalaryOverride(key, isSalary);
    await _loadRows();
    notifyListeners();
  }

  Future<void> setCategory(
    StatementRow row,
    String name,
    SpendCategoryKind kind,
  ) async {
    final key = row.key;
    if (key == null) return;
    await _store.setCategory(key, name, kind);
    await _loadRows();
    notifyListeners();
  }

  Future<void> deleteAccount(String accountKey) async {
    await _store.deleteAccount(accountKey);
    if (_selected == accountKey) _selected = null;
    await load();
  }
}
