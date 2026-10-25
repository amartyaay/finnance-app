/// Rebuilds the transaction table of a bank statement from positioned words.
///
/// Header-driven, never hard-coded: SBI prints at least four layouts (CBS
/// e-statement, OnlineSBI PDF, the print view, the 2025–26 YONO export — see
/// docs/research/07-sbi-statement.md §1), so the column positions come from the
/// header row on each page.
///
/// Every row is then checked with integer arithmetic,
/// `previous balance − debit + credit = printed balance`. A row that fails is
/// kept and flagged, a debit read as a credit is corrected by the same check,
/// and a statement printed newest-first is reversed. Nothing is silently
/// "fixed": the import screen shows how many rows reconciled.
library;

import '../../domain/statement.dart';
import 'statement_words.dart';

/// A row before classification: what the bank printed, nothing inferred.
class RawStatementRow {
  RawStatementRow({required this.date, required this.firstLine});

  DateTime date;
  bool yearPending = false;
  final int firstLine;
  final List<String> descriptionLines = [];
  final List<String> refParts = [];

  /// Amount tokens: (right edge, paise, column guessed from the header).
  final List<({double x1, int paise, _Column column})> amounts = [];

  String get description => descriptionLines.join(' ').replaceAll(
    RegExp(r'\s+'),
    ' ',
  ).trim();

  /// Lines joined with no separator: SBI wraps narrations at a fixed width and
  /// splits words (`SBI C` / `REDIT CARD`), so keyword matching uses this.
  String get descriptionJoined => descriptionLines.join();
}

enum _Column { debit, credit, balance }

class _Line {
  _Line(this.page, this.top, this.words);
  final int page;
  final double top;
  final List<PdfWord> words;

  /// Words joined by one space, or by three where the gap is wide enough to
  /// be a column break ("Name : RAHUL VERMA" … "MG ROAD BENGALURU").
  String get text {
    final out = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      if (i > 0) {
        final gap = words[i].x0 - words[i - 1].x1;
        out.write(gap > words[i].height * 1.8 ? '   ' : ' ');
      }
      out.write(words[i].text);
    }
    return out.toString();
  }
  String get lower => text.toLowerCase();
}

class _ColumnModel {
  _ColumnModel({
    required this.dateX0,
    required this.descX0,
    required this.refX0,
    required this.debitX1,
    required this.creditX1,
    required this.balanceX1,
  });

  final double dateX0;
  final double descX0;
  final double? refX0;
  final double debitX1;
  final double creditX1;
  final double balanceX1;

  /// Left edge of the numeric area: halfway from the narration to Debit.
  double get amountZone => descX0 + (debitX1 - descX0) * 0.45;

  _Column nearest(double x1) {
    final dd = (x1 - debitX1).abs();
    final dc = (x1 - creditX1).abs();
    final db = (x1 - balanceX1).abs();
    if (db <= dd && db <= dc) return _Column.balance;
    return dd <= dc ? _Column.debit : _Column.credit;
  }
}

class StatementTableBuilder {
  const StatementTableBuilder();

  static final RegExp _amount = RegExp(
    r'^-?[\d,]+\.\d{2}(?:cr|dr)?$',
    caseSensitive: false,
  );
  static final RegExp _slashDate = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$');
  static final RegExp _dashDate = RegExp(
    r'^(\d{1,2})-([A-Za-z]{3})-(\d{2}|\d{4})$',
  );
  static final RegExp _day = RegExp(r'^\d{1,2}$');
  static final RegExp _year = RegExp(r'^(?:19|20)\d{2}$');
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static final RegExp _terminator = RegExp(
    r'statement summary|end of statement|computer generated|please do not share|'
    r'power of attorney|dr\. count|\bpage no\b',
    caseSensitive: false,
  );
  static final RegExp _branchTrailer = RegExp(r'^at \d{4,5}\b', caseSensitive: false);

  /// Integer paise from `1,12,450.00`, `154765.60Cr`, `-1,111.00`, `2618072.00Dr`.
  /// String arithmetic only: money is never a double.
  static int? toPaise(String token) {
    final t = token.trim();
    if (!_amount.hasMatch(t)) return null;
    final lower = t.toLowerCase();
    var negative = t.startsWith('-') || lower.endsWith('dr');
    final digits = lower
        .replaceAll(RegExp(r'(cr|dr)$'), '')
        .replaceAll(',', '')
        .replaceAll('-', '');
    final parts = digits.split('.');
    final value = int.parse(parts[0]) * 100 + int.parse(parts[1]);
    if (value == 0) negative = false;
    return negative ? -value : value;
  }

  BankStatement build(List<PdfWord> words) {
    final lines = _lines(words);
    final warnings = <String>[];

    // ---- Metadata (any line; the YONO summary sits at the end) ----------
    final allText = lines.map((l) => l.text).toList();
    final meta = _metadata(allText);

    // ---- Table ----------------------------------------------------------
    _ColumnModel? model;
    var inTable = false;
    final rows = <RawStatementRow>[];
    RawStatementRow? current;
    int? broughtForward;
    int? lastYear = meta.periodFrom?.year;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final header = _header(line, i + 1 < lines.length ? lines[i + 1] : null);
      if (header != null) {
        model = header;
        inTable = true;
        current = null;
        continue;
      }
      if (model == null) continue;
      if (_terminator.hasMatch(line.text)) {
        inTable = false;
        current = null;
        continue;
      }
      if (!inTable) {
        // A continuation page without its own header reuses the last model,
        // but only once a dated row shows up.
        if (_rowDate(line, model, lastYear) == null) continue;
        inTable = true;
      }

      final lower = line.lower;
      if (lower.contains('brought forward')) {
        broughtForward ??= _lastAmount(line);
        current = null;
        continue;
      }
      if (lower.contains('carried forward')) {
        current = null;
        continue;
      }

      final date = _rowDate(line, model, lastYear);
      if (date != null) {
        current = RawStatementRow(date: date.date, firstLine: i)
          ..yearPending = date.yearPending;
        rows.add(current);
        if (!date.yearPending) lastYear = date.date.year;
      } else if (current == null) {
        continue;
      } else {
        // A wrapped year under the date ("1 Sep" / "2026").
        final yearWord = line.words
            .where((w) => w.x0 < model!.descX0 - 2 && _year.hasMatch(w.text))
            .firstOrNull;
        if (yearWord != null && current.yearPending) {
          final y = int.parse(yearWord.text);
          current.date = DateTime(y, current.date.month, current.date.day);
          current.yearPending = false;
          lastYear = y;
        }
      }

      _collectCells(line, model, current);
    }

    // Rows whose year never printed take the running year.
    for (final row in rows.where((r) => r.yearPending)) {
      final y = lastYear ?? DateTime.now().year;
      row.date = DateTime(y, row.date.month, row.date.day);
    }

    final opening = meta.opening ?? broughtForward;
    final built = _reconcile(rows, opening, warnings);

    return BankStatement(
      bank: meta.isSbi ? 'SBI' : 'Bank',
      accountMask: meta.last4,
      holderName: meta.holder,
      periodFrom: meta.periodFrom,
      periodTo: meta.periodTo,
      openingBalancePaise: opening,
      closingBalancePaise:
          meta.closing ?? (built.isNotEmpty ? built.last.balancePaise : null),
      rows: built,
      warnings: warnings,
    );
  }

  // ---- Lines ---------------------------------------------------------------

  List<_Line> _lines(List<PdfWord> words) {
    final sorted = [...words]
      ..sort((a, b) {
        final byPage = a.page.compareTo(b.page);
        if (byPage != 0) return byPage;
        final byTop = a.top.compareTo(b.top);
        return byTop != 0 ? byTop : a.x0.compareTo(b.x0);
      });
    final lines = <_Line>[];
    for (final word in sorted) {
      final tolerance = (word.height * 0.5).clamp(2.0, 6.0);
      final last = lines.isEmpty ? null : lines.last;
      if (last != null &&
          last.page == word.page &&
          (word.top - last.top).abs() <= tolerance) {
        last.words.add(word);
      } else {
        lines.add(_Line(word.page, word.top, [word]));
      }
    }
    for (final line in lines) {
      line.words.sort((a, b) => a.x0.compareTo(b.x0));
    }
    return lines;
  }

  // ---- Header ---------------------------------------------------------------

  static final RegExp _descLabel = RegExp(
    r'^(?:description|details|narration|particulars)$',
    caseSensitive: false,
  );

  _ColumnModel? _header(_Line line, _Line? next) {
    final lower = line.lower;
    if (!lower.contains('date')) return null;
    final desc = line.words.where((w) => _descLabel.hasMatch(_clean(w.text)));
    if (desc.isEmpty) return null;
    PdfWord? find(String label) => line.words
        .where((w) => _clean(w.text).toLowerCase() == label)
        .firstOrNull;
    final debit = find('debit') ?? find('withdrawal') ?? find('withdrawals');
    final credit = find('credit') ?? find('deposit') ?? find('deposits');
    final balance = find('balance');
    if (debit == null || credit == null || balance == null) return null;
    final ref = line.words
        .where((w) => RegExp(r'^(?:ref|chq|cheque)', caseSensitive: false)
            .hasMatch(_clean(w.text)))
        .firstOrNull;
    return _ColumnModel(
      dateX0: line.words.first.x0,
      descX0: desc.first.x0,
      refX0: ref != null && ref.x0 > desc.first.x0 ? ref.x0 : null,
      debitX1: debit.x1,
      creditX1: credit.x1,
      balanceX1: balance.x1,
    );
  }

  String _clean(String text) =>
      text.replaceAll(RegExp(r'[₹.:/()]'), '').trim();

  // ---- Dates ----------------------------------------------------------------

  ({DateTime date, bool yearPending})? _rowDate(
    _Line line,
    _ColumnModel model,
    int? fallbackYear,
  ) {
    final band = line.words.where((w) => w.x0 < model.descX0 - 2).toList();
    if (band.isEmpty) return null;
    final first = band.first.text;

    final slash = _slashDate.firstMatch(first);
    if (slash != null) {
      final day = int.parse(slash.group(1)!);
      final month = int.parse(slash.group(2)!);
      var year = int.parse(slash.group(3)!);
      if (year < 100) year += year < 70 ? 2000 : 1900;
      return _valid(year, month, day, pending: false);
    }
    final dash = _dashDate.firstMatch(first);
    if (dash != null) {
      final month = _months[dash.group(2)!.toLowerCase()];
      if (month == null) return null;
      var year = int.parse(dash.group(3)!);
      if (year < 100) year += year < 70 ? 2000 : 1900;
      return _valid(year, month, int.parse(dash.group(1)!), pending: false);
    }
    if (_day.hasMatch(first) && band.length >= 2) {
      final month = _months[band[1].text.toLowerCase().replaceAll('.', '')];
      if (month == null) return null;
      final day = int.parse(first);
      if (band.length >= 3 && _year.hasMatch(band[2].text)) {
        return _valid(int.parse(band[2].text), month, day, pending: false);
      }
      return _valid(fallbackYear ?? DateTime.now().year, month, day, pending: true);
    }
    return null;
  }

  ({DateTime date, bool yearPending})? _valid(
    int year,
    int month,
    int day, {
    required bool pending,
  }) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month) return null; // 31 Feb
    return (date: date, yearPending: pending);
  }

  // ---- Cells ----------------------------------------------------------------

  void _collectCells(_Line line, _ColumnModel model, RawStatementRow row) {
    final desc = <String>[];
    final ref = <String>[];
    for (final word in line.words) {
      final text = word.text;
      // Date / value-date band — only date-shaped tokens: layout A's header
      // prints "Details" a character right of where the narration starts.
      if (word.x0 < model.descX0 - 2 && _isDateish(text)) continue;
      final paise = toPaise(text);
      if (paise != null && word.x1 >= model.amountZone) {
        row.amounts.add((x1: word.x1, paise: paise, column: model.nearest(word.x1)));
        continue;
      }
      if (text == '-' && word.x0 >= model.amountZone) continue; // empty cell
      final refX0 = model.refX0;
      if (refX0 != null && word.x0 >= refX0 - 2) {
        if (word.x1 < model.amountZone || paise == null) ref.add(text);
      } else {
        desc.add(text);
      }
    }
    final descText = desc.join(' ').trim();
    if (descText.isNotEmpty && !_branchTrailer.hasMatch(descText)) {
      row.descriptionLines.add(descText);
    }
    if (ref.isNotEmpty) row.refParts.add(ref.join(' '));
  }

  bool _isDateish(String text) {
    final t = text.replaceAll(RegExp(r'[()]'), '');
    return _slashDate.hasMatch(t) ||
        _dashDate.hasMatch(t) ||
        _day.hasMatch(t) ||
        _year.hasMatch(t) ||
        _months.containsKey(t.toLowerCase().replaceAll('.', ''));
  }

  int? _lastAmount(_Line line) {
    for (final word in line.words.reversed) {
      final paise = toPaise(word.text);
      if (paise != null) return paise;
    }
    return null;
  }

  // ---- Arithmetic -----------------------------------------------------------

  List<StatementRow> _reconcile(
    List<RawStatementRow> raw,
    int? opening,
    List<String> warnings,
  ) {
    // Turn cells into (debit, credit, balance). The rightmost figure is the
    // balance; any other non-zero figure is the movement, in the column whose
    // header it sits under.
    final parsed = <({RawStatementRow raw, int debit, int credit, int? balance})>[];
    var noAmount = 0;
    for (final row in raw) {
      if (row.amounts.isEmpty) {
        noAmount++;
        continue;
      }
      final byX = [...row.amounts]..sort((a, b) => a.x1.compareTo(b.x1));
      int? balance;
      var rest = byX;
      if (byX.length >= 2 || byX.last.column == _Column.balance) {
        balance = byX.last.paise;
        rest = byX.sublist(0, byX.length - 1);
      }
      var debit = 0;
      var credit = 0;
      for (final a in rest) {
        if (a.paise == 0) continue;
        if (a.column == _Column.credit) {
          credit += a.paise.abs();
        } else {
          debit += a.paise.abs();
        }
      }
      if (debit == 0 && credit == 0) {
        noAmount++; // e.g. `CR RT CHG 7.100`, an interest-rate notice
        continue;
      }
      parsed.add((raw: row, debit: debit, credit: credit, balance: balance));
    }
    if (noAmount > 0) {
      warnings.add('$noAmount line(s) had no amount and were skipped.');
    }
    if (parsed.isEmpty) return const [];

    // Newest-first files (some OnlineSBI downloads): reverse when the dates run
    // backwards.
    var ordered = parsed;
    if (parsed.first.raw.date.isAfter(parsed.last.raw.date)) {
      ordered = parsed.reversed.toList();
      warnings.add('Rows were printed newest first; read them oldest first.');
    }

    final out = <StatementRow>[];
    var previous = opening;
    var corrected = 0;
    var unverified = 0;
    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      var debit = p.debit;
      var credit = p.credit;
      var verified = false;
      final balance = p.balance;
      if (previous != null && balance != null) {
        if (previous - debit + credit == balance) {
          verified = true;
        } else if (previous + debit - credit == balance) {
          // The figure sat closer to the other column header: the balance
          // decides the direction, never the position.
          final swap = debit;
          debit = credit;
          credit = swap;
          verified = true;
          corrected++;
        }
      } else if (previous == null && balance != null && i + 1 < ordered.length) {
        // No opening balance: the first row is confirmed by the next one.
        verified = false;
      }
      if (!verified) unverified++;
      out.add(StatementRow(
        date: p.raw.date,
        description: p.raw.description,
        reference: p.raw.refParts.isEmpty ? null : p.raw.refParts.join(' '),
        debitPaise: debit,
        creditPaise: credit,
        balancePaise: balance,
        balanceVerified: verified,
      ));
      previous = balance ?? (previous == null ? null : previous - debit + credit);
    }
    if (corrected > 0) {
      warnings.add('$corrected row(s) had debit and credit swapped by position; '
          'the running balance corrected them.');
    }
    if (unverified > 0) {
      warnings.add('$unverified of ${out.length} row(s) did not reconcile with '
          'the running balance.');
    }
    return out;
  }

  // ---- Metadata -------------------------------------------------------------

  ({
    String? last4,
    String? holder,
    DateTime? periodFrom,
    DateTime? periodTo,
    int? opening,
    int? closing,
    bool isSbi,
  }) _metadata(List<String> lines) {
    String? last4;
    String? holder;
    DateTime? from;
    DateTime? to;
    int? opening;
    int? closing;
    var isSbi = false;
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('sbin') || lower.contains('state bank of india')) {
        isSbi = true;
      }
      final account = RegExp(
        r'account\s*(?:no|number)\.?\s*:?\s*[_xX*\d\s]*?(\d{4})\b(?!\d)',
        caseSensitive: false,
      ).firstMatch(line);
      if (last4 == null && account != null) last4 = account.group(1);
      final name = RegExp(
        r'^(?:account\s+)?name\s*:\s*(?:(?:mr|mrs|ms|miss|dr|smt)\.?\s+)?([A-Za-z][A-Za-z .]{1,60}?)\s*(?:\s{2,}|$)',
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (holder == null && name != null) holder = name.group(1)!.trim();
      final period = RegExp(
        r'(?:statement\s+from|account statement from|for the period)\s*:?\s*'
        r'(.+?)\s+to\s+(\S+(?:\s+[A-Za-z]{3}\s+\d{4})?)',
        caseSensitive: false,
      ).firstMatch(line);
      if (from == null && period != null) {
        from = parseLooseDate(period.group(1)!);
        to = parseLooseDate(period.group(2)!);
      }
      if (opening == null) {
        final asOn = RegExp(r'balance as on', caseSensitive: false).hasMatch(line);
        final ob = RegExp(r'opening balance\s*:?\s*(-?[\d,]+\.\d{2})', caseSensitive: false)
            .firstMatch(line);
        if (ob != null) {
          opening = toPaise(ob.group(1)!);
        } else if (asOn) {
          final amounts = RegExp(r'-?[\d,]+\.\d{2}(?:cr|dr)?', caseSensitive: false)
              .allMatches(line)
              .toList();
          if (amounts.isNotEmpty) opening = toPaise(amounts.last.group(0)!);
        }
      }
      final cb = RegExp(r'closing balance\s*:?\s*(-?[\d,]+\.\d{2})', caseSensitive: false)
          .firstMatch(line);
      if (cb != null) closing = toPaise(cb.group(1)!);
    }
    return (
      last4: last4,
      holder: holder,
      periodFrom: from,
      periodTo: to,
      opening: opening,
      closing: closing,
      isSbi: isSbi,
    );
  }

  /// `01/09/2026`, `01/09/26`, `1 Sep 2026`, `01-Sep-26`.
  static DateTime? parseLooseDate(String text) {
    final t = text.trim();
    final slash = _slashDate.firstMatch(t);
    if (slash != null) {
      var y = int.parse(slash.group(3)!);
      if (y < 100) y += 2000;
      return DateTime(y, int.parse(slash.group(2)!), int.parse(slash.group(1)!));
    }
    final dash = _dashDate.firstMatch(t);
    if (dash != null) {
      final m = _months[dash.group(2)!.toLowerCase()];
      var y = int.parse(dash.group(3)!);
      if (y < 100) y += 2000;
      return m == null ? null : DateTime(y, m, int.parse(dash.group(1)!));
    }
    final words = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})$').firstMatch(t);
    if (words != null) {
      final m = _months[words.group(2)!.toLowerCase()];
      return m == null
          ? null
          : DateTime(int.parse(words.group(3)!), m, int.parse(words.group(1)!));
    }
    return null;
  }
}
