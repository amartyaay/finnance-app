/// Core enums shared by the parser, the engines and the UI.
library;

/// What a message or a transaction *is*, financially.
enum TxnKind {
  /// Money the user actually spent (goods/services).
  spend,

  /// Cash taken out of an ATM — movement of cash, not consumption. Counted in
  /// cashflow but excluded from category spend so it does not double-count the
  /// purchases the cash is later used for.
  cash,

  /// Money came in (salary, refund, cashback, P2P receive).
  income,

  /// Movement between the user's own accounts: card bill payment, self transfer,
  /// wallet/UPI-Lite top-up, investment/demat transfer, FD/RD.
  transfer;

  bool get isSpendLike => this == spend;
  bool get affectsCashflow => this == spend || this == cash || this == income;
}

/// How the money moved.
enum Instrument {
  upi,
  creditCard,
  debitCard,
  bankAccount,
  wallet,
  atm,
  emi,
  unknown;

  String get label => switch (this) {
    upi => 'UPI',
    creditCard => 'Credit card',
    debitCard => 'Debit card',
    bankAccount => 'Bank',
    wallet => 'Wallet',
    atm => 'ATM',
    emi => 'EMI',
    unknown => 'Unknown',
  };
}

/// Where a message landed in the classifier.
enum SmsClass {
  /// A real debit/credit we can turn into a transaction.
  transaction,

  /// Real but not a transaction: OTP, statement, limit reminder, bill due.
  informational,

  /// Marketing / cross-sell, sometimes from the bank itself.
  promo,

  /// Impersonation, KYC lure, credential theft, fake refunds.
  phishing,

  /// Cannot decide — surfaced in a "needs review" bucket rather than dropped.
  unknown;

  bool get isTrustedSpendSource => this == transaction;
}

/// Provenance of a transaction category.
enum CategorySource {
  /// Matched a bundled merchant rule.
  rule,

  /// Derived from UPI VPA / bank narration heuristics.
  heuristic,

  /// Chosen by the user (wins over everything).
  user,

  none,
}

/// Why a transaction was classified as a transfer (kept for explainability).
enum TransferReason {
  creditCardBill,
  selfTransfer,
  walletLoad,
  investment,
  loanRepayment,
  none;

  String get label => switch (this) {
    creditCardBill => 'Credit-card bill payment',
    selfTransfer => 'Between your own accounts',
    walletLoad => 'Wallet / UPI Lite load',
    investment => 'Investment',
    loanRepayment => 'Loan / EMI repayment',
    none => 'Transfer',
  };
}

/// Trust level of the SMS sender id (all offline heuristics).
enum SenderTrust {
  /// Bundled registry hit: a known bank/wallet DLT header.
  known,

  /// Plausible transactional header but not in the registry.
  plausible,

  /// Numeric / +91 / unregistered header, or a lookalike of a known one.
  suspicious,
}

/// Coarse intent used for iconography and filtering in the UI.
enum SpendCategoryKind {
  food,
  groceries,
  transport,
  shopping,
  bills,
  rent,
  entertainment,
  health,
  education,
  travel,
  fuel,
  investments,
  transfers,
  income,
  cash,
  other,
}
