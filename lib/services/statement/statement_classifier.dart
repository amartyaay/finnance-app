/// What a statement row *is*: kind, counterparty and category, from SBI's
/// narration vocabulary (docs/research/07-sbi-statement.md §3).
///
/// The column (debit or credit) is the direction and always wins over a
/// `TO`/`BY` prefix. Keywords are matched on the narration with every space
/// removed, because SBI wraps at a fixed width and splits words mid-token
/// (`SBI C` / `REDIT CARD`, `BIGBASKE` / `T`).
library;

import '../../domain/enums.dart';
import '../../domain/statement.dart';
import '../../engine/salary_cycles.dart';
import '../categorizer.dart';

class StatementClassifier {
  const StatementClassifier({this.categorizer = const Categorizer()});

  final Categorizer categorizer;

  static RegExp _r(String pattern) => RegExp(pattern, caseSensitive: false);

  static final _cash = _r(r'ATMWDL|ATMCASH|CASHWITHDRAWAL|CASHCHEQUE|CHEQUEWDL|CSHWDL|CASHWDL');
  static final _cashDeposit = _r(r'CASHDEPOSIT|CSHDEP|CDMDEP|BYCASH');
  static final _charges = _r(
    r'CHGS|CHARGES|ANNUALFEE|ANNUALMAINT|PROCESSINGFEE|FEEDEBIT|MINBAL|NONMAINT|'
    r'GSTON|TAXDEDUCTION|DEBITINTEREST|TAXONPREVIOUS|SMSCHG',
  );
  static final _cardBill = _r(
    r'CRED(?:CLUB|\.CLUB|/)|^CRED|CHEQ|SBICARD|SBICREDITCARD|CREDITCARD|CCPAYMENT|'
    r'CCPAY|AMEX|AMERICANEXPRESS|ONECARD|SCAPIA|UNICARDS|CARDPAYMENT|CARDBILL',
  );
  static final _investment = _r(
    r'ZERODHA|GR[O0]WW|UPSTOX|ICCL|BSELTD|BSEL|NSECLEARING|MUTUALFUND|MUTUAL|'
    r'(?:^|[^A-Z])MF(?:[^A-Z]|$)|KUVERA|PPF|NPSTRUST|(?:^|[^A-Z])SIP(?:[^A-Z]|$)|'
    r'INDIANCLEARING|ANGELONE|RENEWAL|TDR|STDR|SWEEP|FIXEDDEPOSIT|RECURRINGDEPOSIT',
  );
  static final _loan = _r(r'LOAN|(?:^|[^A-Z])EMI(?:[^A-Z]|$)|BAJAJFIN|HOMEFIN|NBFC');
  static final _refund = _r(r'REFUND|REVERSAL|(?:^|[^A-Z])REV(?:[^A-Z]|$)|CHARGEBACK|RETURN');
  static final _cashback = _r(r'CASHBACK|REWARD|(?:^|[^A-Z])CR_');
  static final _interest = _r(r'INTERESTCREDIT|CREDITINTEREST|INT\.?PD|SBINT|DIVIDEND|INTCREDIT');
  static final _wallet = _r(r'PAYTMWALLET|UPILITE|MOBIKWIK|WALLETLOAD|ADDMONEY');
  static final _selfWords = _r(r'\bSELF\b|\bOWN A/?C\b');
  static final _card = _r(r'DEBITCARD|OTHPG|SBIPG|OTHPOS|SBIPOS|POSATMPURCH|POSPURCH|ECOMPUR');
  static final _billpay = _r(r'BILLPAY|BBPS');
  static final _bulk = _r(r'BULKPOSTING|CEMTEX');

  /// `UPI/DR/<rrn>/<name>/<bank>/<vpa>/<note>`; layout A prints only
  /// `UPI/DR/<rrn>/ <name>`, so the later fields are optional.
  static final _upi = RegExp(
    r'UPI/(DR|CR)/(\d{6,})/\s*([^/]*)(?:/([^/]*))?(?:/([^/]*))?(?:/(.*))?',
    caseSensitive: false,
  );
  static final _neft = RegExp(r'NEFT\*([A-Z]{4}0[A-Z0-9]{6})\*([A-Z0-9 ]+)\*([^*]+)', caseSensitive: false);

  /// The 2026 OnlineSBI PDF spaces the stars and runs the remitter on after
  /// the UTR: `NEFT * CITI0000006 * CITIN26661516108 DELOITTE CONSUL 0099…`.
  static final _neftSpaced = RegExp(
    r'NEFT\s*\*\s*([A-Z]{4}0[A-Z0-9]{6})\s*\*\s*([A-Z0-9]+(?:\s*\*\s*[A-Z0-9]+)?)\s+([A-Z][A-Z .&]*?)(?=\s+\d{6,}|\s+AT\s+\d{4,5}|$)',
    caseSensitive: false,
  );
  static final _personalHandle = RegExp(
    r'@ok(?:sbi|hdfcbank|icici|axis)|@ibl|@axl|@upi|^\d{10}@|@apl|@yapl',
    caseSensitive: false,
  );
  static final _merchantHandle = RegExp(
    r'\.stor|razorpay|bharatpe|paytmqr|payu|cashfree|billdesk|@hdfcbank|@icici\b|'
    r'@axisbank|@yesb|@ybl.*\d{6}|merchant|\.rzp|pinelabs|ezetap',
    caseSensitive: false,
  );
  static final _business = RegExp(
    r'\b(?:PVT|LTD|LIMITED|LLP|INDIA|TECHNOLOGIES|TECH|STORE|STORES|MART|ENTERPRISES?|'
    r'TRADERS|MEDICAL|PHARMA|FUEL|SERVICES|FOODS?|CAFE|HOTEL|RESTAURANT|SUPERMARKET|'
    r'AGENCY|CENTRE|CENTER|M/?S)\b',
    caseSensitive: false,
  );

  StatementRow classify(StatementRow row, {String? holderName}) {
    final spaced = row.description.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    final joined = spaced.replaceAll(' ', '');
    final debit = row.isDebit;

    final upi = _upi.firstMatch(spaced);
    final neft = _neft.firstMatch(spaced) ?? _neftSpaced.firstMatch(spaced);
    final counterparty = _counterparty(spaced, upi, neft);
    final vpa = upi?.group(5)?.trim() ?? '';
    final note = upi?.group(6)?.trim() ?? '';

    StatementRow as(StatementKind kind, {String? category, SpendCategoryKind? categoryKind}) {
      final c = category == null
          ? _category(kind, counterparty, spaced)
          : (name: category, kind: categoryKind ?? SpendCategoryKind.other);
      return row.copyWith(
        kind: kind,
        counterparty: counterparty,
        categoryName: c.name,
        categoryKind: c.kind,
      );
    }

    if (_isSelf(spaced, joined, counterparty, holderName)) {
      return as(StatementKind.selfTransfer);
    }

    if (debit) {
      if (_cash.hasMatch(joined)) return as(StatementKind.cash);
      if (_charges.hasMatch(joined)) {
        return as(StatementKind.charges,
            category: 'Bills & utilities', categoryKind: SpendCategoryKind.bills);
      }
      if (_cardBill.hasMatch(joined)) return as(StatementKind.cardBill);
      if (_investment.hasMatch(joined)) return as(StatementKind.investment);
      if (_loan.hasMatch(joined)) return as(StatementKind.loan);
      if (_wallet.hasMatch(joined)) return as(StatementKind.selfTransfer);
      if (_card.hasMatch(joined)) return as(StatementKind.spend);
      if (_billpay.hasMatch(joined)) {
        final c = _category(StatementKind.spend, counterparty, spaced);
        return c.kind == SpendCategoryKind.other
            ? as(StatementKind.spend,
                category: 'Bills & utilities', categoryKind: SpendCategoryKind.bills)
            : as(StatementKind.spend);
      }
      if (upi != null || joined.contains('IMPS') || neft != null || joined.contains('INB')) {
        // A personal VPA decides first: "rent sept" in the note is a
        // category hint, not proof of a shop.
        if (_looksLikePerson(counterparty, vpa)) {
          if (RegExp(r'\bRENT\b').hasMatch(note) || joined.contains('RENT')) {
            return as(StatementKind.toPerson,
                category: 'Rent', categoryKind: SpendCategoryKind.rent);
          }
          return as(StatementKind.toPerson);
        }
        return as(StatementKind.spend);
      }
      return as(StatementKind.otherDebit);
    }

    // Credits.
    if (_refund.hasMatch(joined)) return as(StatementKind.refund);
    if (_cashback.hasMatch(joined)) return as(StatementKind.cashback);
    if (_interest.hasMatch(joined)) return as(StatementKind.interest);
    if (SalaryDetector.mentionsSalary(joined)) return as(StatementKind.salary);
    if (_cashDeposit.hasMatch(joined)) return as(StatementKind.selfTransfer);
    if (_cardBill.hasMatch(joined)) return as(StatementKind.otherCredit);
    if (_investment.hasMatch(joined)) return as(StatementKind.redemption);
    if (_loan.hasMatch(joined)) return as(StatementKind.loan);
    if (neft != null || _bulk.hasMatch(joined) || joined.contains('RTGS')) {
      return as(StatementKind.otherCredit); // salary candidate
    }
    if (upi != null && _looksLikePerson(counterparty, vpa)) {
      return as(StatementKind.fromPerson);
    }
    return as(StatementKind.otherCredit);
  }

  /// UPI name field, then NEFT remitter, then the card-gateway merchant, then
  /// the bill-pay biller. Cleaned for display ("ACME SOFTWARE PVT").
  String? _counterparty(String spaced, RegExpMatch? upi, RegExpMatch? neft) {
    String? clean(String? raw) {
      if (raw == null) return null;
      final t = raw
          .replaceAll(RegExp(r'-+\s*$'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return t.isEmpty ? null : t;
    }

    if (upi != null) {
      final name = clean(upi.group(3));
      if (name != null) return name;
      return clean(upi.group(5));
    }
    if (neft != null) return clean(neft.group(3));
    final card = RegExp(r'(?:OTHPG|SBIPG|OTHPOS|SBIPOS)\s*\d{6,}\s*([A-Z][A-Z .&]{2,40})')
        .firstMatch(spaced.replaceAll(RegExp(r'(\d{6})\s+(\d)'), r'$1$2'));
    if (card != null) return clean(card.group(1));
    final bill = RegExp(r'BILLPAY\s*~?\s*IB\d+\s+([A-Z][A-Z .]{2,30})').firstMatch(spaced);
    if (bill != null) return clean(bill.group(1));
    return null;
  }

  bool _isSelf(String spaced, String joined, String? counterparty, String? holder) {
    // Word test on the spaced text: joined, "HDFC SELF" reads "HDFCSELF".
    if (_selfWords.hasMatch(spaced)) return true;
    if (holder == null || holder.trim().isEmpty) return false;
    final h = holder.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (h.length < 6) return false;
    final c = (counterparty ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (c.length >= 6 && (c.contains(h) || h.contains(c))) return true;
    // "TRANSFER FROM Mr. AMARTYAAYUSHI" with the holder printed spaced.
    return joined.contains(h);
  }

  bool _looksLikePerson(String? name, String vpa) {
    if (_merchantHandle.hasMatch(vpa)) return false;
    if (name != null && _business.hasMatch(name)) return false;
    if (_personalHandle.hasMatch(vpa)) return true;
    if (name == null) return false;
    if (RegExp(r'^(?:MR|MRS|MS|MISS|DR|SMT)\.?\s', caseSensitive: false).hasMatch(name)) {
      return true;
    }
    // "RAMESH K", "PRIYA S": a given name and an initial is how SBI prints a
    // person when the VPA is not shown (layout A).
    return RegExp(r'^[A-Z]{3,}(?: [A-Z]{3,})? [A-Z]$').hasMatch(name.toUpperCase());
  }

  ({String name, SpendCategoryKind kind}) _category(
    StatementKind kind,
    String? counterparty,
    String narration,
  ) {
    switch (kind) {
      case StatementKind.cash:
        return (name: 'Cash', kind: SpendCategoryKind.cash);
      case StatementKind.investment:
      case StatementKind.redemption:
        return (name: 'Investments', kind: SpendCategoryKind.investments);
      case StatementKind.salary:
      case StatementKind.interest:
        return (name: 'Income', kind: SpendCategoryKind.income);
      case StatementKind.selfTransfer:
      case StatementKind.cardBill:
      case StatementKind.toPerson:
      case StatementKind.fromPerson:
      case StatementKind.loan:
        return (name: 'Transfers', kind: SpendCategoryKind.transfers);
      default:
        break;
    }
    final byName = categorizer.categorize(counterparty, kind: TxnKind.spend);
    if (byName.kind != SpendCategoryKind.other) return byName;
    return categorizer.categorize(narration, kind: TxnKind.spend);
  }
}
