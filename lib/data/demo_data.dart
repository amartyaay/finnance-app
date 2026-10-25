import 'dart:math';

import '../domain/enums.dart';
import '../domain/sms_message.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';

/// A realistic, deterministic demo dataset so the app can be explored (and
/// reviewed) without reading anyone's real SMS.
///
/// Shaped like a Bengaluru salaried professional in their late twenties:
/// UPI-heavy, quick-commerce groceries, food delivery, two credit cards with
/// different limits, rent, a SIP, subscriptions, a salary credit, a card bill
/// payment, one duplicate charge and one phishing attempt.
class DemoDataset {
  DemoDataset({DateTime? now, this.seed = 7}) : now = now ?? DateTime.now() {
    _build();
  }

  final DateTime now;
  final int seed;

  final List<Txn> transactions = [];
  final List<CardAccount> cards = [];
  final List<CardBillNotice> bills = [];
  final List<SmsMessage> sms = [];
  final List<SmsAssessment> assessments = [];

  static const List<String> categories = [
    'Food & dining',
    'Groceries',
    'Transport',
    'Shopping',
    'Bills & utilities',
    'Rent',
    'Entertainment',
    'Health',
    'Travel',
    'Fuel',
    'Investments',
    'Transfers',
    'Income',
    'Cash',
    'Other',
  ];

  late final CardAccount hdfcCard;
  late final CardAccount iciciCard;
  late final CardAccount amexCard;

  void _build() {
    hdfcCard = CardAccount(
      id: 1,
      issuer: 'HDFC Bank',
      last4: '4821',
      label: 'HDFC Millennia',
      creditLimitPaise: 150000 * 100,
      statementDay: 12,
      dueDay: 2,
    );
    iciciCard = CardAccount(
      id: 2,
      issuer: 'ICICI Bank',
      last4: '9077',
      label: 'ICICI Coral',
      creditLimitPaise: 250000 * 100,
      statementDay: 5,
      dueDay: 25,
    );
    amexCard = CardAccount(
      id: 3,
      issuer: 'American Express',
      last4: '3005',
      label: 'Amex Platinum Travel',
      creditLimitPaise: 400000 * 100,
      statementDay: 20,
      dueDay: 10,
    );
    cards.addAll([hdfcCard, iciciCard, amexCard]);

    final rng = Random(seed);
    final monthStart = DateTime(now.year, now.month);

    // ---- Fixed monthly obligations (last 4 months) ------------------------
    for (var back = 3; back >= 0; back--) {
      final month = DateTime(now.year, now.month - back);
      _add(
        at: DateTime(month.year, month.month, 1, 9, 12),
        amount: 2400000,
        merchant: 'Sobha Elite Rent',
        kind: TxnKind.spend,
        instrument: Instrument.upi,
        category: 'Rent',
        categoryKind: SpendCategoryKind.rent,
        vpa: 'sobhaelite@ybl',
      );
      _add(
        at: DateTime(month.year, month.month, 1, 9, 30),
        amount: 12500000,
        merchant: 'Salary - Helios Tech',
        kind: TxnKind.income,
        instrument: Instrument.bankAccount,
        category: 'Income',
        categoryKind: SpendCategoryKind.income,
        sender: 'HDFCBK',
      );
      _add(
        at: DateTime(month.year, month.month, 3, 7, 45),
        amount: 1500000,
        merchant: 'Groww SIP',
        kind: TxnKind.transfer,
        instrument: Instrument.bankAccount,
        category: 'Investments',
        categoryKind: SpendCategoryKind.investments,
        transferReason: TransferReason.investment,
      );
      _add(
        at: DateTime(month.year, month.month, 4, 20, 5),
        amount: 64900,
        merchant: 'Netflix',
        kind: TxnKind.spend,
        instrument: Instrument.creditCard,
        category: 'Entertainment',
        categoryKind: SpendCategoryKind.entertainment,
        card: hdfcCard,
      );
      _add(
        at: DateTime(month.year, month.month, 6, 11, 0),
        amount: 11900,
        merchant: 'Spotify',
        kind: TxnKind.spend,
        instrument: Instrument.creditCard,
        category: 'Entertainment',
        categoryKind: SpendCategoryKind.entertainment,
        card: iciciCard,
      );
      _add(
        at: DateTime(month.year, month.month, 7, 18, 40),
        amount: 199900,
        merchant: 'Cult.fit',
        kind: TxnKind.spend,
        instrument: Instrument.creditCard,
        category: 'Health',
        categoryKind: SpendCategoryKind.health,
        card: hdfcCard,
      );
      _add(
        at: DateTime(month.year, month.month, 9, 13, 20),
        amount: 99900,
        merchant: 'Airtel Postpaid',
        kind: TxnKind.spend,
        instrument: Instrument.upi,
        category: 'Bills & utilities',
        categoryKind: SpendCategoryKind.bills,
      );
      _add(
        at: DateTime(month.year, month.month, 11, 19, 0),
        amount: 145000,
        merchant: 'BESCOM Electricity',
        kind: TxnKind.spend,
        instrument: Instrument.upi,
        category: 'Bills & utilities',
        categoryKind: SpendCategoryKind.bills,
      );

    }

    // ---- Day-to-day spending for the last 100 days -------------------------
    final merchants = <_Merchant>[
      _Merchant('Swiggy', 'Food & dining', SpendCategoryKind.food, 38000, 92000, 5, Instrument.upi),
      _Merchant('Zomato', 'Food & dining', SpendCategoryKind.food, 42000, 110000, 3, Instrument.upi),
      _Merchant('Third Wave Coffee', 'Food & dining', SpendCategoryKind.food, 22000, 48000, 4, Instrument.upi),
      _Merchant('Blinkit', 'Groceries', SpendCategoryKind.groceries, 24000, 145000, 5, Instrument.upi),
      _Merchant('Zepto', 'Groceries', SpendCategoryKind.groceries, 18000, 82000, 3, Instrument.upi),
      _Merchant('BigBasket', 'Groceries', SpendCategoryKind.groceries, 90000, 320000, 1, Instrument.creditCard),
      _Merchant('Uber', 'Transport', SpendCategoryKind.transport, 12000, 54000, 4, Instrument.upi),
      _Merchant('Rapido', 'Transport', SpendCategoryKind.transport, 8000, 22000, 3, Instrument.upi),
      _Merchant('Amazon', 'Shopping', SpendCategoryKind.shopping, 29000, 480000, 2, Instrument.creditCard),
      _Merchant('Flipkart', 'Shopping', SpendCategoryKind.shopping, 45000, 260000, 1, Instrument.creditCard),
      _Merchant('Nykaa', 'Shopping', SpendCategoryKind.shopping, 60000, 180000, 1, Instrument.creditCard),
      _Merchant('Indian Oil', 'Fuel', SpendCategoryKind.fuel, 150000, 350000, 2, Instrument.creditCard),
      _Merchant('Apollo Pharmacy', 'Health', SpendCategoryKind.health, 22000, 120000, 1, Instrument.upi),
      _Merchant('BookMyShow', 'Entertainment', SpendCategoryKind.entertainment, 45000, 140000, 1, Instrument.creditCard),
      _Merchant('IRCTC', 'Travel', SpendCategoryKind.travel, 95000, 240000, 1, Instrument.upi),
    ];

    for (var dayOffset = 0; dayOffset <= 100; dayOffset++) {
      final day = now.subtract(Duration(days: dayOffset));
      for (final merchant in merchants) {
        if (rng.nextInt(100) > merchant.frequency * 6) continue;
        final amount = merchant.min + rng.nextInt(merchant.max - merchant.min);
        final card = switch (merchant.instrument) {
          Instrument.creditCard => rng.nextBool() ? hdfcCard : iciciCard,
          _ => null,
        };
        _add(
          at: DateTime(day.year, day.month, day.day, 8 + rng.nextInt(13), rng.nextInt(60)),
          amount: amount,
          merchant: merchant.name,
          kind: TxnKind.spend,
          instrument: merchant.instrument,
          category: merchant.category,
          categoryKind: merchant.kind,
          card: card,
        );
      }
    }

    // ---- Two recent big-ticket purchases ----------------------------------
    _add(
      at: DateTime(monthStart.year, monthStart.month, max(1, now.day - 4), 17, 25),
      amount: 4499000,
      merchant: 'Croma',
      kind: TxnKind.spend,
      instrument: Instrument.creditCard,
      category: 'Shopping',
      categoryKind: SpendCategoryKind.shopping,
      card: hdfcCard,
    );
    _add(
      at: DateTime(monthStart.year, monthStart.month, max(1, now.day - 9), 20, 40),
      amount: 1285000,
      merchant: 'Taj Palace',
      kind: TxnKind.spend,
      instrument: Instrument.creditCard,
      category: 'Travel',
      categoryKind: SpendCategoryKind.travel,
      card: amexCard,
    );

    // ---- A duplicate charge and an ATM withdrawal ------------------------
    _add(
      at: DateTime(monthStart.year, monthStart.month, max(1, now.day - 2), 13, 5),
      amount: 48000,
      merchant: 'Swiggy',
      kind: TxnKind.spend,
      instrument: Instrument.upi,
      category: 'Food & dining',
      categoryKind: SpendCategoryKind.food,
    );
    _add(
      at: DateTime(monthStart.year, monthStart.month, max(1, now.day - 2), 13, 11),
      amount: 48000,
      merchant: 'Swiggy',
      kind: TxnKind.spend,
      instrument: Instrument.upi,
      category: 'Food & dining',
      categoryKind: SpendCategoryKind.food,
    );
    _add(
      at: DateTime(monthStart.year, monthStart.month, max(1, now.day - 6), 19, 10),
      amount: 500000,
      merchant: 'ATM HDFC Indiranagar',
      kind: TxnKind.cash,
      instrument: Instrument.atm,
      category: 'Cash',
      categoryKind: SpendCategoryKind.cash,
      transferReason: TransferReason.none,
    );

// ---- Card bill payments, sized to what each card actually spent --------
    // Only closed cycles are settled, so the current balance is realistic.
    for (final card in cards) {
      for (var back = 2; back <= 4; back++) {
        final month = DateTime(now.year, now.month - back);
        final spent = transactions
            .where(
              (t) =>
                  t.cardKey == '${card.issuer}|${card.last4}' &&
                  t.kind == TxnKind.spend &&
                  t.occurredAt.year == month.year &&
                  t.occurredAt.month == month.month,
            )
            .fold<int>(0, (sum, t) => sum + t.amountPaise);
        if (spent <= 0) continue;
        _add(
          at: DateTime(month.year, month.month, 22, 10, 5),
          amount: spent,
          merchant: '${card.displayName} bill payment',
          kind: TxnKind.transfer,
          instrument: Instrument.bankAccount,
          category: 'Transfers',
          categoryKind: SpendCategoryKind.transfers,
          transferReason: TransferReason.creditCardBill,
          card: card,
        );
      }
    }

    // ---- Bills + limits reported in SMS ----------------------------------
    // Bills are derived from the previous cycle's real spend, so the amount due
    // and the outstanding balance always agree.
    for (final card in [hdfcCard, iciciCard]) {
      final key = '${card.issuer}|${card.last4}';
      final previousCycle = transactions
          .where(
            (t) =>
                t.cardKey == key &&
                t.kind == TxnKind.spend &&
                t.occurredAt.isAfter(now.subtract(const Duration(days: 62))) &&
                t.occurredAt.isBefore(now.subtract(const Duration(days: 31))),
          )
          .fold<int>(0, (sum, t) => sum + t.amountPaise);
      if (previousCycle <= 0) continue;
      final dueDay = card.dueDay ?? 2;
      final due = DateTime(now.year, now.month, dueDay);
      final dueMs = (due.isBefore(DateTime(now.year, now.month, now.day))
              ? DateTime(now.year, now.month + 1, dueDay)
              : due)
          .millisecondsSinceEpoch;
      bills.add(
        CardBillNotice(
          cardKey: key,
          totalDuePaise: previousCycle,
          minimumDuePaise: (previousCycle * 0.05).round(),
          dueDateMs: dueMs,
          receivedAtMs: now.subtract(const Duration(days: 9)).millisecondsSinceEpoch,
        ),
      );
    }

    _buildSms();
  }

  void _add({
    required DateTime at,
    required int amount,
    required String merchant,
    required TxnKind kind,
    required Instrument instrument,
    required String category,
    required SpendCategoryKind categoryKind,
    CardAccount? card,
    String? vpa,
    TransferReason transferReason = TransferReason.none,
    String? sender,
    bool needsReview = false,
  }) {
    if (at.isAfter(now)) return;
    final index = transactions.length;
    transactions.add(
      Txn(
        key: 'demo:$index',
        occurredAtMs: at.millisecondsSinceEpoch,
        amountPaise: amount,
        kind: kind,
        instrument: instrument,
        sender: sender ?? (card?.issuer ?? 'HDFCBK'),
        merchant: merchant,
        counterpartyVpa: vpa,
        categoryName: category,
        categoryKind: categoryKind,
        categorySource: CategorySource.rule,
        transferReason: transferReason,
        cardKey: card == null ? null : '${card.issuer}|${card.last4}',
        last4: card?.last4,
        issuer: card?.issuer,
        confidence: needsReview ? 0.45 : 0.92,
        needsReview: needsReview,
      ),
    );
  }

  void _buildSms() {
    final samples = <(String, String, SmsClass, String)>[
      (
        'VM-HDFCBK-T',
        'Rs.480.00 debited from a/c XX4412 on 05-06-26 to Swiggy via UPI. '
            'UPI Ref 126038293410. Avl Bal Rs.42,180.55',
        SmsClass.transaction,
        'Genuine UPI debit',
      ),
      (
        'VK-ICICIB-T',
        'INR 8,999.00 spent on ICICI Bank Credit Card XX9077 on 07-Jun-26 at Croma. '
            'Avl Limit: INR 1,42,000.00',
        SmsClass.transaction,
        'Card spend with available limit',
      ),
      (
        'AD-HDFCBK-P',
        'Get 10% cashback on your HDFC Bank Credit Card at BigBasket this weekend. '
            'T&C apply. To stop receiving, reply STOP.',
        SmsClass.promo,
        'Marketing from a real bank header',
      ),
      (
        'AD-KYCVERIFY',
        'Dear customer, your SBI account will be BLOCKED in 24 hrs. '
            'Update KYC now: http://sbi-kyc-verify.xyz/login',
        SmsClass.phishing,
        'KYC phishing with lookalike domain',
      ),
      (
        'VM-HDFCBK-T',
        'Your OTP for HDFC Bank netbanking is 481920. Valid for 10 min. '
            'Do NOT share it with anyone.',
        SmsClass.informational,
        'OTP — never a transaction',
      ),
      (
        'VM-ICICIB-T',
        'Payment of Rs.18,452 received on your ICICI Bank Credit Card XX9077. '
            'Thank you for your payment.',
        SmsClass.transaction,
        'Card bill payment — a transfer, not spend',
      ),
      ('+919845012233', 'Hi, this is Rakesh from courier. Your parcel is held at customs, pay Rs.250 to this UPI: rakesh@ybl', SmsClass.phishing, 'Personal-number delivery scam'),
    ];

    for (var i = 0; i < samples.length; i++) {
      final (sender, body, cls, reason) = samples[i];
      final message = SmsMessage(
        id: 'demo-sms-$i',
        sender: sender,
        body: body,
        receivedAtMs: now.subtract(Duration(hours: i * 7)).millisecondsSinceEpoch,
      );
      sms.add(message);
      assessments.add(
        SmsAssessment(
          cls: cls,
          score: cls == SmsClass.transaction ? 0.93 : 0.88,
          signals: [SmsSignal(reason, cls == SmsClass.transaction ? 6 : -6, detail: reason)],
          senderTrust: cls == SmsClass.phishing
              ? SenderTrust.suspicious
              : SenderTrust.known,
        ),
      );
    }
  }
}

class _Merchant {
  const _Merchant(
    this.name,
    this.category,
    this.kind,
    this.min,
    this.max,
    this.frequency,
    this.instrument,
  );

  final String name;
  final String category;
  final SpendCategoryKind kind;
  final int min;
  final int max;
  final int frequency;
  final Instrument instrument;
}
