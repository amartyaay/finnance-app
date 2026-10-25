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

  /// Money came in **and it is income**: salary, interest, pension, dividend.
  /// A refund, a card-bill credit, a wallet load or a move between the user's
  /// own accounts is *not* income — see [MoneyInKind] and [TxnKind.transfer].
  income,

  /// Money moved without being consumption or income: card bill payment, self
  /// transfer, refund, cashback, wallet/UPI-Lite top-up, investment redemption,
  /// FD/RD, loan repayment.
  transfer;

  bool get isSpendLike => this == spend;
  bool get affectsCashflow => this == spend || this == cash || this == income;
}

/// Why money came **in**. The dashboard's "Came in" and the savings rate may
/// only use [isTrueIncome]; everything else is reported separately so a card
/// bill payment or a refund can never look like a salary.
///
/// Persisted on `transactions.money_in_kind`; `none` means "not an inflow".
enum MoneyInKind {
  /// Salary / wages — the only inflow that makes a savings rate meaningful.
  salary,

  /// Bank interest, FD/RD interest, dividend, pension.
  interest,

  /// A genuine income credit whose source we cannot name (business receipt,
  /// stipend, bonus). Still income, but never assumed from an anonymous credit.
  other,

  /// Money returned for an earlier purchase (merchant refund, reversal).
  refund,

  /// Reward credit from a card/wallet programme.
  cashback,

  /// A payment **credited to the user's own credit card** — the card bill being
  /// paid off. A transfer, never income.
  cardPayment,

  /// A credit leg that is really the user's own money changing accounts.
  selfTransfer,

  /// Proceeds of an investment/FD/TD being redeemed — principal coming back.
  redemption,

  /// A meal/flexi/UPI-Lite wallet top-up.
  walletLoad,

  /// A credit from another person (P2P). Their money, not the user's income.
  p2pReceive,

  /// Not an inflow.
  none;

  /// True only for money the user actually earned or was paid as income.
  bool get isTrueIncome => this == salary || this == interest || this == other;

  bool get isInflow => this != none;

  String get label => switch (this) {
    salary => 'Salary',
    interest => 'Interest',
    other => 'Other income',
    refund => 'Refund',
    cashback => 'Cashback',
    cardPayment => 'Card bill payment',
    selfTransfer => 'Between your own accounts',
    redemption => 'Redemption',
    walletLoad => 'Wallet load',
    p2pReceive => 'Received from a person',
    none => '',
  };

  /// The transfer reason that carries this inflow on a `Txn`.
  TransferReason get asTransferReason => switch (this) {
    cardPayment => TransferReason.creditCardBill,
    refund => TransferReason.refund,
    cashback => TransferReason.cashback,
    redemption => TransferReason.redemption,
    walletLoad => TransferReason.walletLoad,
    p2pReceive => TransferReason.personTransfer,
    selfTransfer => TransferReason.selfTransfer,
    _ => TransferReason.none,
  };
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

  /// Matched a rule the user taught the app (`merchant_rules`).
  learned,

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

  /// A payout to, or a credit from, another *person* (P2P UPI, named NEFT
  /// beneficiary). Not "between your own accounts" — that wording was wrong.
  personTransfer,
  walletLoad,
  investment,

  /// Money returned for an earlier purchase.
  refund,

  /// A reward credit from a card/wallet programme.
  cashback,

  /// An FD/TD/mutual-fund redemption paying the principal back.
  redemption,
  loanRepayment,
  none;

  String get label => switch (this) {
    creditCardBill => 'Credit-card bill payment',
    selfTransfer => 'Between your own accounts',
    personTransfer => 'To / from a person',
    walletLoad => 'Wallet / UPI Lite load',
    investment => 'Investment',
    refund => 'Refund',
    cashback => 'Cashback',
    redemption => 'Redemption',
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
