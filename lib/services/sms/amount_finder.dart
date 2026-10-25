import '../../domain/money.dart';

/// One `₹…` (or bare) number found in an SMS body, with the evidence that it is
/// (or is not) the transaction amount.
class AmountCandidate {
  const AmountCandidate({
    required this.paise,
    required this.start,
    required this.end,
    required this.score,
    required this.reason,
    this.hasCurrencyMark = true,
  });

  final int paise;
  final int start;
  final int end;
  final int score;
  final String reason;
  final bool hasCurrencyMark;

  @override
  String toString() =>
      'AmountCandidate(${paise / 100}, score=$score, $reason)';
}

/// Finds every plausible money amount in an SMS and scores how likely it is to
/// be *the* transaction amount rather than a balance, a limit, an OTP or a date.
///
/// This is the single most error-prone part of Indian SMS parsing: a typical
/// alert contains two or three numbers ("debited Rs 250, Avl Bal Rs 9,500,
/// Ref 123456789"). Scoring beats "take the first match" on every real corpus.
class AmountFinder {
  const AmountFinder();

  /// Currency-marked numbers: `Rs 250`, `Rs.1,299.50`, `INR 5000`, `₹ 99`.
  ///
  /// Indian bank statements print `Total amt: INR Dr. 11660.26` — the debit
  /// mark sits between the currency and the figure, and without it every Axis
  /// statement had no parsable amount at all.
  static final RegExp _currency = RegExp(
    r'(?:(?:rs|inr)\.?|₹)\s*(?:(?:dr|cr|debit|credit)\.?\s*)?'
    r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// Bare numbers that follow a money verb: `debited 250`, `credited by 1,000`.
  static final RegExp _bareAfterVerb = RegExp(
    r'\b(?:debited|credited|spent|paid|sent|received|withdrawn|withdrew|charged|deposited|refunded|reversed|transferred)\b'
    r'(?:\s+(?:by|with|of|for|is|rs|inr|amount|amt))?\s*'
    r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  List<AmountCandidate> findAll(String body) {
    final lower = body.toLowerCase();
    final results = <AmountCandidate>[];
    final seen = <int>{};

    for (final match in _currency.allMatches(body)) {
      final paise = parseAmountToPaise(match.group(1)!);
      if (paise == null || paise.value <= 0) continue;
      if (!seen.add(match.start)) continue;
      results.add(
        AmountCandidate(
          paise: paise.value,
          start: match.start,
          end: match.end,
          score: _score(body, lower, match.start, match.end, currency: true),
          reason: _reason(body, lower, match.start, match.end, currency: true),
        ),
      );
    }

    for (final match in _bareAfterVerb.allMatches(body)) {
      if (match.start >= 1 && body[match.start - 1] == '₹') continue;
      final groupStart = match.start + match.group(0)!.indexOf(match.group(1)!);
      if (!seen.add(groupStart)) continue;
      final paise = parseAmountToPaise(match.group(1)!);
      if (paise == null || paise.value <= 0) continue;
      results.add(
        AmountCandidate(
          paise: paise.value,
          start: groupStart,
          end: groupStart + match.group(1)!.length,
          score: _score(body, lower, groupStart, groupStart, currency: false),
          reason: 'bare amount after money verb',
          hasCurrencyMark: false,
        ),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Highest-scoring candidate, or null when the SMS has no usable amount.
  AmountCandidate? best(String body) {
    final all = findAll(body);
    if (all.isEmpty) return null;
    return all.first;
  }

  /// The amount that follows a balance label, if any (`Avl Bal Rs 9,500`).
  AmountCandidate? balanceAfter(String body) {
    final lower = body.toLowerCase();
    final label = RegExp(
      r'\b(?:avl(?:ailable)?\.?\s*(?:bal(?:ance)?|limit)|bal(?:ance)?(?:\s*(?:is|now|:))?|'
      r'available\s+balance|updated\s+balance|remaining\s+balance|closing\s+balance)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (label == null) return null;

    for (final candidate in findAll(body)) {
      if (candidate.start >= label.end - 4 &&
          candidate.start <= label.end + 40) {
        return candidate;
      }
    }
    return null;
  }

  /// `Available limit` / `Avl Lmt` on a credit-card alert.
  AmountCandidate? availableLimit(String body) {
    final lower = body.toLowerCase();
    final label = RegExp(
      r'\b(?:avl|available)\.?\s*(?:credit\s*)?(?:lmt|limit)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (label == null) return null;
    for (final candidate in findAll(body)) {
      if (candidate.start >= label.end - 6 &&
          candidate.start <= label.end + 40) {
        return candidate;
      }
    }
    return null;
  }

  /// `Total limit` / `Credit Limit` on a credit-card alert.
  AmountCandidate? totalLimit(String body) {
    final lower = body.toLowerCase();
    final label = RegExp(
      r'\b(?:total|overall|sanctioned)?\s*(?:credit\s*)?(?:card\s*)?(?:lmt|limit)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (label == null) return null;
    if (lower.contains('available limit') || lower.contains('avl lmt')) {
      final idx = lower.indexOf('available');
      final alt = lower.indexOf('avl lmt');
      final firstAvail = idx >= 0 ? idx : alt;
      if (firstAvail >= 0 && label.start >= firstAvail - 2) return null;
    }
    for (final candidate in findAll(body)) {
      if (candidate.start >= label.end - 6 &&
          candidate.start <= label.end + 40) {
        return candidate;
      }
    }
    return null;
  }

  int _score(
    String body,
    String lower,
    int start,
    int end, {
    required bool currency,
  }) {
    final windowStart = (start - 60).clamp(0, lower.length);
    final windowEnd = (end + 45).clamp(0, lower.length);
    final before = lower.substring(windowStart, start.clamp(0, lower.length));
    final after = lower.substring(end.clamp(0, lower.length), windowEnd);

    var score = currency ? 2 : 0;

    final debitVerb = RegExp(
      r'\b(debited|spent|paid|sent|purchase[d]?|charged|withdrawn|withdrew|transferred|billed|deducted)\b',
    );
    final creditVerb = RegExp(
      r'\b(credited|received|refund(?:ed)?|reversed|reversal|cashback|deposited)\b',
    );

    // Indian alerts put the verb before the amount ("debited Rs 250") roughly as
    // often as after it ("Rs 250 debited"), so both windows must count.
    if (debitVerb.hasMatch(before)) score += 6;
    if (creditVerb.hasMatch(before)) score += 5;
    if (debitVerb.hasMatch(after)) score += 5;
    if (creditVerb.hasMatch(after)) score += 4;

    // A money *request* is not a payment; the amount belongs to someone else.
    if (RegExp(r'\b(requested|request|collect)\b').hasMatch('$before $after')) {
      score -= 9;
    }
    // Top-ups and deposits move money without a debit verb.
    if (RegExp(r'\b(?:added\s+to|top\s*up|topup|loaded|recharged|deposited)\b')
        .hasMatch('$before $after')) {
      score += 4;
    }
    // "credited with INR 5,000" / "debited by Rs 250" are amount anchors.
    if (RegExp(r'\b(?:of|for|by|with|amount|amt)\s*$').hasMatch(before)) score += 2;

    // Balance / limit context strongly suggests "not the txn amount".
    if (RegExp(
      r'(bal(?:ance)?|avl|available|limit|lmt|outstanding|due|minimum)',
    ).hasMatch(before.replaceAll(RegExp(r'[^a-z]'), ''))) {
      score -= 7;
    }
    if (RegExp(r'^\s*(?:only)?\s*(?:as|is)?\s*(?:your)?\s*(?:avl|available|bal)')
        .hasMatch(after)) {
      score -= 5;
    }

    // OTP / validity context.
    final whole = '$before$after';
    if (RegExp(r'\b(otp|o\.t\.p|valid for|do not share|never share)\b')
        .hasMatch(whole)) {
      score -= 8;
    }

    // Dates, times, years, card/account numbers.
    if (RegExp(r'\d\s*[-/]\s*$').hasMatch(before) ||
        RegExp(r'^\s*[-/]\s*\d').hasMatch(after)) {
      score -= 6;
    }
    if (RegExp(r'\d\s*:\s*$').hasMatch(before)) score -= 6;
    if (!currency && (RegExp(r'^(?:19|20)\d{2}$').hasMatch(body.substring(start, end)))) {
      score -= 8;
    }
    // Only a mask *adjacent* to the number discounts it. An account mask earlier
    // in the sentence belongs to the account, not to the amount: in
    // `A/c XX1234 debited Rs 2,000` the ±6/±6 used to cancel the debit verb and
    // the transaction was dropped (F02/F03, tx-02/tx-11).
    if (RegExp(
      r'(?:[x*]{1,8}[\s-]*\d{3,5}|\bending\s*(?:no\.?\s*)?\d{2,5}|'
      r'\b(?:a/?c|acc(?:ount)?)\s*(?:no\.?\s*)?[x*]{0,8}\s*\d{2,5}|'
      r'\bcard\s*(?:no\.?\s*)?[x*]{0,8}\s*\d{2,5})[\s:.*-]*$',
    ).hasMatch(before)) {
      score -= 6;
    }
    if (RegExp(r'\b(month|year|days?|%|p\.?a\.?|apr|emi\s+of)\b').hasMatch(after)) {
      score -= 3;
    }
    // "Rs 1,299.00 Dr" — a trailing debit mark confirms.
    if (RegExp(r'^\s*(dr|debit|db)\b').hasMatch(after)) score += 3;
    if (RegExp(r'^\s*(cr|credit)\b').hasMatch(after)) score += 2;

    return score;
  }

  String _reason(
    String body,
    String lower,
    int start,
    int end, {
    required bool currency,
  }) {
    final before = lower.substring((start - 40).clamp(0, lower.length), start);
    if (RegExp(r'\b(debited|spent|paid|sent|charged|withdrawn)\b').hasMatch(before)) {
      return 'follows a debit verb';
    }
    if (RegExp(r'\b(credited|received|refund|reversed)\b').hasMatch(before)) {
      return 'follows a credit verb';
    }
    if (RegExp(r'(bal|avl|available|limit|lmt)').hasMatch(before)) {
      return 'looks like balance/limit';
    }
    return currency ? 'currency-marked amount' : 'bare number';
  }
}
