import 'dart:math';

import '../models/sms_message_record.dart';
import '../models/transaction_models.dart';

abstract class SmsParserService {
  ParsedTransaction? parse(SmsMessageRecord record);
}

class DefaultSmsParserService implements SmsParserService {
  DefaultSmsParserService({SmsSenderCatalog? catalog})
    : catalog = catalog ?? const SmsSenderCatalog();

  final SmsSenderCatalog catalog;

  static final RegExp _otpPattern = RegExp(
    r'\b(otp|one time password|verification code|verification otp|do not share|never share)\b',
    caseSensitive: false,
  );
  static final RegExp _statementPattern = RegExp(
    r'\b(statement|mini statement|e-statement|account summary)\b',
    caseSensitive: false,
  );
  static final RegExp _promoPattern = RegExp(
    r'\b(offer|loan offer|pre-approved|promo|promotion|advertisement|apply now|limited time)\b',
    caseSensitive: false,
  );
  static final RegExp _creditLikePattern = RegExp(
    r'\b(credited|credit received|received|refund|reversal|reversed|cashback|cash back|returned|deposited|failed|declined|unsuccessful)\b',
    caseSensitive: false,
  );
  static final RegExp _debitLikePattern = RegExp(
    r'\b(debited|debited with|spent|spent on|paid|payment|purchase|purchased|charged|withdrawn|sent|transferred|used|billed)\b',
    caseSensitive: false,
  );
  static final RegExp _creditCardBillPaymentPattern = RegExp(
    r'\b(?:credit\s*card|cc|card)\s*(?:bill|payment|repayment|dues?|outstanding|statement)\b|'
    r'\b(?:billpay|billdesk|bbps|bharat\s+bill\s*pay|cred|cheq)\b.{0,80}\b(?:credit\s*card|card\s*bill|cc)\b|'
    r'\b(?:paid|payment|debited|sent|transferred)\b.{0,80}\b(?:sbi\s*card|hdfc\s*(?:bank\s*)?credit\s*card|icici\s*(?:bank\s*)?credit\s*card|axis\s*(?:bank\s*)?credit\s*card|kotak\s*credit\s*card)\b',
    caseSensitive: false,
  );
  static final RegExp _storedValueLoadPattern = RegExp(
    r'\b(?:upi\s*lite|wallet)\b.{0,60}\b(?:top\s*up|load(?:ed)?|add(?:ed)?\s+money|recharge)\b|'
    r'\b(?:top\s*up|load(?:ed)?|add(?:ed)?\s+money|recharge)\b.{0,60}\b(?:upi\s*lite|wallet)\b',
    caseSensitive: false,
  );
  static final RegExp _selfTransferPattern = RegExp(
    r'\b(?:self\s*transfer|own\s+account|to\s+your\s+(?:own\s+)?a/?c|between\s+your\s+accounts|to\s+self)\b',
    caseSensitive: false,
  );
  static final RegExp _investmentTransferPattern = RegExp(
    r'\b(?:mutual\s*fund|sip|systematic\s+investment|demat|broker|zerodha|groww|upstox|indmoney|smallcase|nps|ppf|fixed\s+deposit|recurring\s+deposit|fd|rd)\b',
    caseSensitive: false,
  );
  static final RegExp _amountPattern = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _merchantPattern = RegExp(
    r'\b(?:at|to|towards|for|on)\s+([A-Za-z0-9][A-Za-z0-9 .&@_-]{2,50})',
    caseSensitive: false,
  );
  static final RegExp _accountHintPattern = RegExp(
    r'\b(?:a/?c|acct|account|card|debit card|credit card|ending)\s*[x*#-]*\s*([0-9]{2,4})\b',
    caseSensitive: false,
  );
  static final RegExp _referencePattern = RegExp(
    r'\b(?:upi\s*(?:ref(?:erence)?|txn|transaction)?\s*(?:no\.?|id)?|utr|rrn|ref(?:erence)?\s*(?:no\.?|id)?|txn\s*(?:id|no\.?)|transaction\s*(?:id|no\.?))\s*[:#-]?\s*([A-Z0-9]{6,24})\b',
    caseSensitive: false,
  );

  @override
  ParsedTransaction? parse(SmsMessageRecord record) {
    final body = record.body.trim();
    if (body.isEmpty) {
      return null;
    }

    final lowerBody = body.toLowerCase();
    if (_otpPattern.hasMatch(lowerBody) ||
        _statementPattern.hasMatch(lowerBody) ||
        _promoPattern.hasMatch(lowerBody)) {
      return null;
    }

    if (_creditLikePattern.hasMatch(lowerBody)) {
      return null;
    }

    if (!_debitLikePattern.hasMatch(lowerBody) &&
        !lowerBody.contains('upi') &&
        !lowerBody.contains('wallet') &&
        !lowerBody.contains('card')) {
      return null;
    }

    final amountMatch = _findAmountMatch(body, lowerBody);
    if (amountMatch == null) {
      return null;
    }

    final amountPaise = _toPaise(amountMatch.group(1)!);
    if (amountPaise <= 0) {
      return null;
    }

    final normalizedSender = catalog.normalize(record.sender);
    final senderProfile = catalog.lookup(normalizedSender);
    final instrument = _detectInstrument(lowerBody, senderProfile);
    final merchant = _extractMerchant(body);
    final accountHint = _extractAccountHint(body);
    final referenceId = _extractReferenceId(body);
    final direction = _detectDirection(lowerBody);

    return ParsedTransaction(
      sourceSmsId: _buildSourceSmsId(record, normalizedSender, amountPaise),
      sender: record.sender,
      normalizedSender: normalizedSender,
      timestampMillis: record.timestampMillis,
      amountPaise: amountPaise,
      direction: direction,
      instrument: instrument,
      accountOrCardHint: accountHint,
      merchantOrPayee: merchant,
      referenceId: referenceId,
      confidence: _confidenceScore(
        senderProfile: senderProfile,
        lowerBody: lowerBody,
        instrument: instrument,
        merchant: merchant,
      ),
    );
  }

  Match? _findAmountMatch(String body, String lowerBody) {
    final matches = _amountPattern.allMatches(body).toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }

    Match? bestMatch;
    var bestScore = -999;
    for (final match in matches) {
      final score = _scoreAmountMatch(match, lowerBody);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = match;
      }
    }

    return bestMatch;
  }

  int _scoreAmountMatch(Match match, String lowerBody) {
    final start = max(0, match.start - 70);
    final end = min(lowerBody.length, match.end + 70);
    final window = lowerBody.substring(start, end);

    var score = 0;
    if (_debitLikePattern.hasMatch(window)) {
      score += 4;
    }
    if (window.contains('upi')) {
      score += 2;
    }
    if (window.contains('card')) {
      score += 2;
    }
    if (window.contains('wallet')) {
      score += 1;
    }
    if (window.contains('balance') ||
        window.contains('available') ||
        window.contains('avl') ||
        window.contains('minimum')) {
      score -= 3;
    }
    return score;
  }

  int _toPaise(String rawAmount) {
    final parsed = double.tryParse(rawAmount.replaceAll(',', ''));
    if (parsed == null) {
      return 0;
    }
    return (parsed * 100).round();
  }

  TransactionInstrument _detectInstrument(
    String lowerBody,
    SmsSenderProfile? senderProfile,
  ) {
    if (lowerBody.contains('upi') ||
        lowerBody.contains('@upi') ||
        lowerBody.contains(' vpa ') ||
        lowerBody.contains('upi ref') ||
        lowerBody.contains('upiid')) {
      return TransactionInstrument.upi;
    }
    if (lowerBody.contains('wallet') ||
        lowerBody.contains('paytm') ||
        lowerBody.contains('phonepe') ||
        lowerBody.contains('google pay') ||
        lowerBody.contains('gpay') ||
        lowerBody.contains('amazon pay')) {
      return TransactionInstrument.wallet;
    }
    if (lowerBody.contains('credit card') || lowerBody.contains('card used')) {
      return TransactionInstrument.creditCard;
    }
    if (lowerBody.contains('debit card') ||
        lowerBody.contains('atm card') ||
        lowerBody.contains('card ending') ||
        lowerBody.contains('card xx') ||
        lowerBody.contains('card x')) {
      return TransactionInstrument.debitCard;
    }
    if (lowerBody.contains('account') || lowerBody.contains('a/c')) {
      return TransactionInstrument.account;
    }
    return senderProfile?.suggestedInstrument ?? TransactionInstrument.unknown;
  }

  TransactionDirection _detectDirection(String lowerBody) {
    if (_creditCardBillPaymentPattern.hasMatch(lowerBody) ||
        _storedValueLoadPattern.hasMatch(lowerBody) ||
        _selfTransferPattern.hasMatch(lowerBody) ||
        _investmentTransferPattern.hasMatch(lowerBody)) {
      return TransactionDirection.transfer;
    }
    return TransactionDirection.expense;
  }

  String? _extractMerchant(String body) {
    final matches = _merchantPattern.allMatches(body).toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }

    for (final match in matches) {
      final candidate = _cleanMerchant(match.group(1)!);
      if (candidate.isNotEmpty && !_merchantNoise(candidate.toLowerCase())) {
        return candidate;
      }
    }

    return null;
  }

  String _cleanMerchant(String value) {
    var cleaned = value.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+on\s+\d.*$', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(via|ref|upi|imps|neft|rtgs|txn|transaction)\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    return cleaned.trim();
  }

  bool _merchantNoise(String candidate) {
    return candidate.isEmpty ||
        candidate.contains('your account') ||
        candidate.contains('a/c') ||
        candidate.contains('bank') ||
        candidate.contains('transaction') ||
        candidate.contains('payment') ||
        candidate.contains('inr') ||
        candidate.contains('rs.') ||
        RegExp(r'\d').hasMatch(candidate);
  }

  String? _extractAccountHint(String body) {
    final match = _accountHintPattern.firstMatch(body);
    if (match == null) {
      return null;
    }
    return match.group(1);
  }

  String? _extractReferenceId(String body) {
    final rawReference = _referencePattern.firstMatch(body)?.group(1);
    if (rawReference == null) {
      return null;
    }
    return rawReference.toUpperCase();
  }

  String _buildSourceSmsId(
    SmsMessageRecord record,
    String normalizedSender,
    int amountPaise,
  ) {
    final fingerprint = [
      normalizedSender,
      record.timestampMillis ~/ 60000,
      amountPaise,
      record.body.trim(),
    ].join('|');
    return 'sms_${_fnv1a64(fingerprint)}';
  }

  double _confidenceScore({
    required SmsSenderProfile? senderProfile,
    required String lowerBody,
    required TransactionInstrument instrument,
    required String? merchant,
  }) {
    var score = 0.45;
    if (senderProfile != null) {
      score += 0.2;
    }
    if (_debitLikePattern.hasMatch(lowerBody)) {
      score += 0.15;
    }
    if (instrument != TransactionInstrument.unknown) {
      score += 0.1;
    }
    if (merchant != null && merchant.isNotEmpty) {
      score += 0.1;
    }
    return score.clamp(0.0, 0.99);
  }
}

String _fnv1a64(String value) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xffffffffffffffff;

  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & mask;
  }

  return hash.toRadixString(16).padLeft(16, '0');
}

class SmsSenderCatalog {
  const SmsSenderCatalog();

  static final Map<String, SmsSenderProfile> _profiles = {
    'HDFCBK': SmsSenderProfile(
      normalizedSender: 'HDFCBK',
      displayName: 'HDFC Bank',
    ),
    'HDFCIN': SmsSenderProfile(
      normalizedSender: 'HDFCIN',
      displayName: 'HDFC Bank',
    ),
    'ICICIB': SmsSenderProfile(
      normalizedSender: 'ICICIB',
      displayName: 'ICICI Bank',
    ),
    'ICICIC': SmsSenderProfile(
      normalizedSender: 'ICICIC',
      displayName: 'ICICI Bank Card',
      suggestedInstrument: TransactionInstrument.creditCard,
    ),
    'AXISBK': SmsSenderProfile(
      normalizedSender: 'AXISBK',
      displayName: 'Axis Bank',
    ),
    'AXISIN': SmsSenderProfile(
      normalizedSender: 'AXISIN',
      displayName: 'Axis Bank',
    ),
    'SBIUPI': SmsSenderProfile(
      normalizedSender: 'SBIUPI',
      displayName: 'State Bank of India',
      suggestedInstrument: TransactionInstrument.upi,
    ),
    'SBICRD': SmsSenderProfile(
      normalizedSender: 'SBICRD',
      displayName: 'State Bank of India Card',
      suggestedInstrument: TransactionInstrument.creditCard,
    ),
    'SBIINB': SmsSenderProfile(
      normalizedSender: 'SBIINB',
      displayName: 'State Bank of India',
    ),
    'KOTAKB': SmsSenderProfile(
      normalizedSender: 'KOTAKB',
      displayName: 'Kotak Mahindra Bank',
    ),
    'KOTAKC': SmsSenderProfile(
      normalizedSender: 'KOTAKC',
      displayName: 'Kotak Card',
      suggestedInstrument: TransactionInstrument.creditCard,
    ),
    'IDFCFB': SmsSenderProfile(
      normalizedSender: 'IDFCFB',
      displayName: 'IDFC FIRST Bank',
    ),
    'CANBNK': SmsSenderProfile(
      normalizedSender: 'CANBNK',
      displayName: 'Canara Bank',
    ),
    'PNBSMS': SmsSenderProfile(
      normalizedSender: 'PNBSMS',
      displayName: 'Punjab National Bank',
    ),
    'BOBTXN': SmsSenderProfile(
      normalizedSender: 'BOBTXN',
      displayName: 'Bank of Baroda',
    ),
    'UNIONB': SmsSenderProfile(
      normalizedSender: 'UNIONB',
      displayName: 'Union Bank of India',
    ),
    'YESBNK': SmsSenderProfile(
      normalizedSender: 'YESBNK',
      displayName: 'Yes Bank',
    ),
    'INDUSB': SmsSenderProfile(
      normalizedSender: 'INDUSB',
      displayName: 'IndusInd Bank',
    ),
    'FEDBNK': SmsSenderProfile(
      normalizedSender: 'FEDBNK',
      displayName: 'Federal Bank',
    ),
    'RBLBNK': SmsSenderProfile(
      normalizedSender: 'RBLBNK',
      displayName: 'RBL Bank',
    ),
    'AUBANK': SmsSenderProfile(
      normalizedSender: 'AUBANK',
      displayName: 'AU Small Finance Bank',
    ),
    'DBSBANK': SmsSenderProfile(
      normalizedSender: 'DBSBANK',
      displayName: 'DBS Bank',
    ),
    'PAYTMB': SmsSenderProfile(
      normalizedSender: 'PAYTMB',
      displayName: 'Paytm Payments Bank',
      suggestedInstrument: TransactionInstrument.wallet,
    ),
    'PHONEP': SmsSenderProfile(
      normalizedSender: 'PHONEP',
      displayName: 'PhonePe',
      suggestedInstrument: TransactionInstrument.wallet,
    ),
    'GPAY': SmsSenderProfile(
      normalizedSender: 'GPAY',
      displayName: 'Google Pay',
      suggestedInstrument: TransactionInstrument.wallet,
    ),
    'GOOGLEP': SmsSenderProfile(
      normalizedSender: 'GOOGLEP',
      displayName: 'Google Pay',
      suggestedInstrument: TransactionInstrument.wallet,
    ),
    'AMZNPAY': SmsSenderProfile(
      normalizedSender: 'AMZNPAY',
      displayName: 'Amazon Pay',
      suggestedInstrument: TransactionInstrument.wallet,
    ),
    'AMAZON': SmsSenderProfile(
      normalizedSender: 'AMAZON',
      displayName: 'Amazon Pay',
      suggestedInstrument: TransactionInstrument.wallet,
    ),
    'UPI': SmsSenderProfile(
      normalizedSender: 'UPI',
      displayName: 'UPI Alerts',
      suggestedInstrument: TransactionInstrument.upi,
    ),
    'CCARD': SmsSenderProfile(
      normalizedSender: 'CCARD',
      displayName: 'Card Alerts',
      suggestedInstrument: TransactionInstrument.creditCard,
    ),
    'DEBITC': SmsSenderProfile(
      normalizedSender: 'DEBITC',
      displayName: 'Debit Card Alerts',
      suggestedInstrument: TransactionInstrument.debitCard,
    ),
  };

  String normalize(String sender) {
    var value = sender.toUpperCase().trim();
    value = value.replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    if (value.isEmpty) {
      return value;
    }

    final parts = value.split('-').where((part) => part.isNotEmpty).toList();
    if (parts.length > 1 && RegExp(r'^[A-Z]{2}$').hasMatch(parts.first)) {
      parts.removeAt(0);
    }
    while (parts.length > 1 && RegExp(r'^[TSPG]$').hasMatch(parts.last)) {
      parts.removeLast();
    }

    return parts.isEmpty ? value.replaceAll('-', '') : parts.join('-');
  }

  SmsSenderProfile? lookup(String normalizedSender) {
    return _profiles[normalizedSender] ??
        _profiles[normalizedSender.replaceAll('-', '')];
  }
}

class SmsSenderProfile {
  const SmsSenderProfile({
    required this.normalizedSender,
    required this.displayName,
    this.suggestedInstrument = TransactionInstrument.unknown,
  });

  final String normalizedSender;
  final String displayName;
  final TransactionInstrument suggestedInstrument;
}
