import '../../domain/enums.dart';
import '../../domain/sms_message.dart';

/// Offline resolution of Indian SMS sender ids (DLT headers).
///
/// India's DLT regime shapes the header as `<prefix>-<entity>-<category>`, e.g.
/// `VM-HDFCBK-T` (VM = verification/transactional, HDFCBK = HDFC Bank, T =
/// transactional). Promotional traffic uses `-P`, service-implicit uses `-S`.
/// The prefix is *not* a trust proof — spoofing still happens — but combined
/// with a known entity code it is the strongest offline signal we have.
class SenderRegistry {
  const SenderRegistry();

  /// Known entity codes -> display name + kind.
  ///
  /// Deliberately a curated list rather than a regex guess: an unknown code
  /// scores as `plausible`, never as `known`.
  static const Map<String, ({String name, String kind})> entities = {
    // Banks
    'HDFCBK': (name: 'HDFC Bank', kind: 'bank'),
    'HDFC': (name: 'HDFC Bank', kind: 'bank'),
    'HDFCIN': (name: 'HDFC Bank', kind: 'bank'),
    'HDFCCC': (name: 'HDFC Bank', kind: 'card'),
    'ICICIB': (name: 'ICICI Bank', kind: 'bank'),
    'ICICI': (name: 'ICICI Bank', kind: 'bank'),
    'ICICIC': (name: 'ICICI Bank', kind: 'card'),
    'ICICIO': (name: 'ICICI Bank', kind: 'bank'),
    'SBIINB': (name: 'State Bank of India', kind: 'bank'),
    'SBIUPI': (name: 'State Bank of India', kind: 'bank'),
    'ATMSBI': (name: 'State Bank of India', kind: 'bank'),
    'SBICRD': (name: 'SBI Card', kind: 'card'),
    'SBISMS': (name: 'State Bank of India', kind: 'bank'),
    'SBICMP': (name: 'State Bank of India', kind: 'bank'),
    'AXISBK': (name: 'Axis Bank', kind: 'bank'),
    'AXISIN': (name: 'Axis Bank', kind: 'bank'),
    'AXIS': (name: 'Axis Bank', kind: 'bank'),
    'KOTAKB': (name: 'Kotak Mahindra Bank', kind: 'bank'),
    'KOTAKC': (name: 'Kotak Mahindra Bank', kind: 'card'),
    'KOTAK': (name: 'Kotak Mahindra Bank', kind: 'bank'),
    'IDFCFB': (name: 'IDFC FIRST Bank', kind: 'bank'),
    'IDFCBK': (name: 'IDFC FIRST Bank', kind: 'bank'),
    'RBLBNK': (name: 'RBL Bank', kind: 'bank'),
    'RBLCRD': (name: 'RBL Bank', kind: 'card'),
    'YESBNK': (name: 'Yes Bank', kind: 'bank'),
    'YESBK': (name: 'Yes Bank', kind: 'bank'),
    'INDUSB': (name: 'IndusInd Bank', kind: 'bank'),
    'INDUS': (name: 'IndusInd Bank', kind: 'bank'),
    'AUBANK': (name: 'AU Small Finance Bank', kind: 'bank'),
    'AUSFBK': (name: 'AU Small Finance Bank', kind: 'bank'),
    'FEDBNK': (name: 'Federal Bank', kind: 'bank'),
    'FDRL': (name: 'Federal Bank', kind: 'bank'),
    'CANBNK': (name: 'Canara Bank', kind: 'bank'),
    'CNRBNK': (name: 'Canara Bank', kind: 'bank'),
    'PNBSMS': (name: 'Punjab National Bank', kind: 'bank'),
    'BOBTXN': (name: 'Bank of Baroda', kind: 'bank'),
    'UNIONB': (name: 'Union Bank of India', kind: 'bank'),
    'BOIIND': (name: 'Bank of India', kind: 'bank'),
    'DBSBANK': (name: 'DBS Bank', kind: 'bank'),
    'SCBANK': (name: 'Standard Chartered', kind: 'bank'),
    'HSBCBK': (name: 'HSBC India', kind: 'bank'),
    'CITIBN': (name: 'Citibank', kind: 'bank'),
    'AMEXIN': (name: 'American Express', kind: 'card'),
    'AMEX': (name: 'American Express', kind: 'card'),
    'ONECRD': (name: 'OneCard', kind: 'card'),
    'CRED': (name: 'CRED', kind: 'card'),
    'SLICE': (name: 'Slice', kind: 'card'),
    'NIYO': (name: 'Niyo', kind: 'bank'),
    'JUPITR': (name: 'Jupiter', kind: 'bank'),
    'FIBNK': (name: 'Fi Money', kind: 'bank'),
    'PAYTM': (name: 'Paytm', kind: 'wallet'),
    'PAYTMB': (name: 'Paytm Payments Bank', kind: 'wallet'),
    'PYTM': (name: 'Paytm', kind: 'wallet'),
    'PHONEP': (name: 'PhonePe', kind: 'wallet'),
    'PHNPE': (name: 'PhonePe', kind: 'wallet'),
    'PHONPE': (name: 'PhonePe', kind: 'wallet'),
    'GPAY': (name: 'Google Pay', kind: 'wallet'),
    'GOOGLEP': (name: 'Google Pay', kind: 'wallet'),
    'AMZNPAY': (name: 'Amazon Pay', kind: 'wallet'),
    'AMAZON': (name: 'Amazon', kind: 'wallet'),
    'BHIM': (name: 'BHIM UPI', kind: 'wallet'),
    'UPI': (name: 'UPI', kind: 'wallet'),
    'MOBIKW': (name: 'MobiKwik', kind: 'wallet'),
    'FREEC': (name: 'Freecharge', kind: 'wallet'),
    'ZERODH': (name: 'Zerodha', kind: 'broker'),
    'GROWW': (name: 'Groww', kind: 'broker'),
    'UPSTOX': (name: 'Upstox', kind: 'broker'),
    'INDDMN': (name: 'INDmoney', kind: 'broker'),
    'MFUTRL': (name: 'Mutual funds', kind: 'broker'),
    'AIRTEL': (name: 'Airtel', kind: 'telecom'),
    'JIO': (name: 'Jio', kind: 'telecom'),
    'JIOPAY': (name: 'Jio', kind: 'telecom'),
    'AIRINF': (name: 'Airtel', kind: 'telecom'),
    'AIRBNK': (name: 'Airtel Payments Bank', kind: 'bank'),
    'CBSSBI': (name: 'SBI', kind: 'bank'),
    'VIIN': (name: 'Vi', kind: 'telecom'),
  };

  /// Merchant-side headers: these send the *shop's* receipt, not the user's
  /// bank alert, so they can never create a ledger row on their own.
  static const Set<String> merchantSenders = {
    'SWIGGY', 'ZEPTON', 'FLPKRT', 'BLNKIT', 'JIOHTT', 'CDMILK', 'PHRMSY',
    'GOVTAP',
  };

  /// Benefit-card headers (meal/flexi cards). They report the user's own wallet
  /// balance, so they *are* real spends, but a repeated alert with the same
  /// amount seconds apart is a duplicate notification, never a second charge.
  static const Set<String> benefitCardSenders = {
    'PLUXEE', 'JMPLUXEE', 'SODEXO', 'JMSODEXO',
  };

  /// True when the DLT header belongs to a merchant/aggregator receipt sender.
  bool isMerchantReceiptSender(SenderId sender) =>
      merchantSenders.contains(sender.normalized);

  /// True when the header belongs to a benefit/flexi-card issuer.
  bool isBenefitCardSender(SenderId sender) =>
      benefitCardSenders.contains(sender.normalized);

  /// DLT prefixes seen in India: verification, transactional, promotional.
  ///
  /// `JM`, `JX`, `TX`, `BT`, `JA`, `AV` and `CD` are observed on real devices
  /// (real inbox §D2); leaving them out left bank alerts with ids like
  /// `JXCBSSBI` / `JMCBSSBI` unable to match the same entity, which broke
  /// same-sender duplicate detection for term-deposit closures.
  static const Set<String> dltPrefixes = {
    'AD', 'AX', 'BP', 'CC', 'CH', 'CP', 'DA', 'DP', 'GA', 'GD', 'GI', 'GM',
    'GO', 'GOV', 'GR', 'GT', 'GV', 'IC', 'JD', 'JK', 'JO', 'JT', 'MS', 'NM',
    'NV', 'OT', 'PU', 'PV', 'RC', 'RD', 'RM', 'SA', 'SD', 'SG', 'SM', 'SP',
    'SS', 'ST', 'SU', 'TD', 'TK', 'TM', 'TN', 'TP', 'TT', 'TU', 'VA', 'VD',
    'VE', 'VF', 'VG', 'VK', 'VM', 'VP', 'VR', 'VS', 'VT', 'VV', 'VW', 'VX',
    'WA', 'WD', 'WT', 'XA', 'XB', 'XC', 'XD', 'XE', 'XF', 'XG', 'XH', 'XI',
    'XJ', 'XK', 'XL', 'XM', 'XN', 'XO', 'XP', 'XQ', 'XR', 'XS', 'XT', 'XU',
    'XV', 'XW', 'XX', 'XY', 'XZ', 'JM', 'JX', 'TX', 'BT', 'JA', 'AV', 'CD',
  };

  /// Common lookalike substitutions used to defeat naive matching.
  static const Map<String, String> _homoglyphs = {
    '0': 'O',
    '1': 'I',
    '5': 'S',
    '8': 'B',
    '|': 'I',
    '!': 'I',
    'l': 'I',
    'i': 'I',
  };

  SenderId resolve(String rawSender) {
    final raw = rawSender.trim();
    final numeric = RegExp(r'^\+?\d[\d\s-]{6,}$').hasMatch(raw);
    if (numeric) {
      return SenderId(
        raw: raw,
        normalized: raw.replaceAll(RegExp(r'[^0-9]'), ''),
        trust: SenderTrust.suspicious,
      );
    }

    // Split on '-'; the last part may be the DLT category letter.
    final parts = raw
        .toUpperCase()
        .split('-')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);

    String? category;
    var body = parts;
    if (body.length >= 2 && RegExp(r'^[TPSGU]$').hasMatch(body.last)) {
      category = body.last;
      body = body.sublist(0, body.length - 1);
    }

    String? prefix;
    if (body.length >= 2 && dltPrefixes.contains(body.first)) {
      prefix = body.first;
      body = body.sublist(1);
    }

    final normalized = body.join('-').replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final entity = entities[normalized] ??
        entities[body.first.replaceAll(RegExp(r'[^A-Z0-9]'), '')];

    if (entity != null) {
      return SenderId(
        raw: raw,
        normalized: normalized,
        trust: SenderTrust.known,
        dltPrefix: prefix,
        dltCategory: category,
        entity: entity.name,
        entityKind: entity.kind,
      );
    }

    // Lookalike of a known entity? e.g. HDFCBANK, ICICIBANK, HDFC-BK.
    final canonical = _canonicalize(normalized);
    for (final entry in entities.entries) {
      final known = _canonicalize(entry.key);
      if (known.length < 4) continue;
      if (canonical == known) continue;
      if (canonical.contains(known) || known.contains(canonical)) {
        // A real header plus a branding word (e.g. HDFCBANK) is normal; a
        // *digit* or odd punctuation substitution is not.
        final digitInSender = RegExp(r'[0-9]').hasMatch(normalized);
        return SenderId(
          raw: raw,
          normalized: normalized,
          trust: digitInSender ? SenderTrust.suspicious : SenderTrust.plausible,
          dltPrefix: prefix,
          dltCategory: category,
          entity: entry.value.name,
          entityKind: entry.value.kind,
        );
      }
    }

    final looksLikeHeader = RegExp(r'^[A-Z]{2,12}$').hasMatch(normalized);
    return SenderId(
      raw: raw,
      normalized: normalized,
      trust: looksLikeHeader ? SenderTrust.plausible : SenderTrust.suspicious,
      dltPrefix: prefix,
      dltCategory: category,
    );
  }

  static String _canonicalize(String value) {
    var out = value.toUpperCase();
    _homoglyphs.forEach((from, to) {
      out = out.replaceAll(from, to);
    });
    return out.replaceAll(RegExp(r'[^A-Z]'), '');
  }

  /// True when the sender's category letter marks promotional traffic.
  bool isPromotionalHeader(SenderId sender) =>
      sender.dltCategory == 'P' || sender.dltCategory == 'S';
}
