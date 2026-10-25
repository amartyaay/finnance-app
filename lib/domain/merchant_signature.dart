/// Stable keys for the two kinds of learned rule.
///
/// The point of a *signature* (rather than the raw merchant string) is that the
/// same shop must produce the same key across alerts: `Pluxee Meal`,
/// `PLUXEE MEAL 4411` and `Pluxee-Mcal` are one merchant to a person, and a
/// rule learned from one alert has to fire on the next.
///
/// The rules are deliberately simple and offline:
///   * lowercase;
///   * punctuation becomes a space (`zomato*order` -> `zomato order`);
///   * trailing digits are dropped (`shop123` -> `shop`, `AMAZON 4411` ->
///     `amazon`) — order ids and store numbers are not part of a brand;
///   * at most the first three tokens survive, so a long bank narration still
///     reduces to the brand.
///
/// A transaction with no merchant falls back to the sender's entity
/// (`HDFC Bank`), which is the best identity the alert offers.
class MerchantSignature {
  const MerchantSignature._();

  /// Number of leading tokens kept. Three is enough for `icici prudential
  /// asset` and short enough that a trailing branch/order string cannot fork a
  /// rule.
  static const int maxTokens = 3;

  /// Normalises a merchant (or sender entity) into a rule key.
  ///
  /// Returns `null` when nothing usable is left, in which case no rule should
  /// be written: a key of `''` would match the whole ledger.
  static String? of(String? merchant, {String? senderEntity}) {
    final raw = merchant?.trim();
    final source = (raw != null && raw.isNotEmpty) ? raw : senderEntity;
    if (source == null) return null;

    final tokens = <String>[];
    for (final token in source.toLowerCase().split(RegExp(r'[^a-z0-9&]+'))) {
      if (token.isEmpty) continue;
      // Strip the trailing digit run from the token itself: `store42` and
      // `store` are the same shop.
      final withoutTail = token.replaceAll(RegExp(r'[0-9]+$'), '');
      if (withoutTail.isEmpty) continue;
      if (RegExp(r'^[0-9]+$').hasMatch(withoutTail)) continue;
      tokens.add(withoutTail);
      if (tokens.length == maxTokens) break;
    }
    return tokens.isEmpty ? null : tokens.join(' ');
  }

  /// True when [of] had to fall back to the sender entity because the row had
  /// no merchant of its own.
  ///
  /// Used to avoid writing a sender-wide rule from a single anonymous spend:
  /// the fallback key covers every alert from that bank, which is only useful
  /// when the user actually picked a meaningful category.
  static bool isSenderFallback(String? merchant) =>
      merchant == null || merchant.trim().isEmpty;

  /// Coarse amount bucket used by the "not a transaction" rule.
  ///
  /// The same shop alert at the same amount is the same shape; the band keeps
  /// small amount drift (rounding, fees) inside one rule while never hiding a
  /// genuinely different purchase.
  static String amountBand(int amountPaise) {
    final rupees = amountPaise / 100;
    if (rupees < 100) return 'lt100';
    if (rupees < 500) return '100-500';
    if (rupees < 1000) return '500-1k';
    if (rupees < 5000) return '1k-5k';
    if (rupees < 10000) return '5k-10k';
    if (rupees < 50000) return '10k-50k';
    return 'ge50k';
  }

  /// Key for a negative rule: sender + merchant + amount band.
  ///
  /// Sender is the normalised DLT header already stored on the transaction, so
  /// two different banks never share an exclusion even when the merchant text
  /// is identical.
  static String exclusion({
    String? sender,
    String? merchant,
    required int amountPaise,
  }) {
    final senderKey = of(sender) ?? 'unknown';
    final merchantKey = of(merchant) ?? 'none';
    return '$senderKey|$merchantKey|${amountBand(amountPaise)}';
  }
}
