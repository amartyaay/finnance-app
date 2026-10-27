import '../domain/enums.dart';
import '../domain/merchant_signature.dart';

/// Offline merchant -> category rules, tuned for Indian merchants.
///
/// Order matters: the first matching pattern wins, so put specific brands
/// before generic words. Patterns are matched against the *normalised* merchant
/// string (lowercase, punctuation collapsed to single spaces).
class Categorizer {
  const Categorizer();

  static const List<(String, String, SpendCategoryKind)> _rules = [
    // Hotels & travel brands (real inbox: JW Marriott, CWT India).
    ('marriott', 'Travel', SpendCategoryKind.travel),
    ('jw marriott', 'Travel', SpendCategoryKind.travel),
    ('taj ', 'Travel', SpendCategoryKind.travel),
    ('itc hotel', 'Travel', SpendCategoryKind.travel),
    ('hyatt', 'Travel', SpendCategoryKind.travel),
    ('radisson', 'Travel', SpendCategoryKind.travel),
    ('novotel', 'Travel', SpendCategoryKind.travel),
    ('ibis', 'Travel', SpendCategoryKind.travel),
    ('leela', 'Travel', SpendCategoryKind.travel),
    ('oberoi', 'Travel', SpendCategoryKind.travel),
    ('sheraton', 'Travel', SpendCategoryKind.travel),
    ('westin', 'Travel', SpendCategoryKind.travel),
    ('cwt india', 'Travel', SpendCategoryKind.travel),

    // Meal-benefit cards (real inbox: Pluxee x24).
    ('pluxee', 'Food & dining', SpendCategoryKind.food),
    ('sodexo', 'Food & dining', SpendCategoryKind.food),

    // Asset managers / SIPs (real inbox: ICICI Prudential, NAV 50-52).
    ('icici prudential', 'Investments', SpendCategoryKind.investments),
    ('hdfc amc', 'Investments', SpendCategoryKind.investments),
    ('axis mf', 'Investments', SpendCategoryKind.investments),
    ('sbi mf', 'Investments', SpendCategoryKind.investments),
    ('kotak mf', 'Investments', SpendCategoryKind.investments),
    ('franklin', 'Investments', SpendCategoryKind.investments),
    ('nippon', 'Investments', SpendCategoryKind.investments),
    ('motilal', 'Investments', SpendCategoryKind.investments),
    ('bandhan', 'Investments', SpendCategoryKind.investments),
    ('kfin', 'Investments', SpendCategoryKind.investments),
    ('prudential', 'Investments', SpendCategoryKind.investments),
    ('amc', 'Investments', SpendCategoryKind.investments),

    // Learning platforms.
    ('takeuforward', 'Education', SpendCategoryKind.education),
    // Food delivery & restaurants
    ('swiggy', 'Food & dining', SpendCategoryKind.food),
    ('zomato', 'Food & dining', SpendCategoryKind.food),
    ('eatsure', 'Food & dining', SpendCategoryKind.food),
    ('dominos', 'Food & dining', SpendCategoryKind.food),
    ('pizza hut', 'Food & dining', SpendCategoryKind.food),
    ('mcdonald', 'Food & dining', SpendCategoryKind.food),
    ('kfc', 'Food & dining', SpendCategoryKind.food),
    ('burger king', 'Food & dining', SpendCategoryKind.food),
    ('starbucks', 'Food & dining', SpendCategoryKind.food),
    ('chaayos', 'Food & dining', SpendCategoryKind.food),
    ('third wave', 'Food & dining', SpendCategoryKind.food),
    ('blue tokai', 'Food & dining', SpendCategoryKind.food),
    ('barbeque', 'Food & dining', SpendCategoryKind.food),
    ('restaurant', 'Food & dining', SpendCategoryKind.food),
    ('cafe', 'Food & dining', SpendCategoryKind.food),
    ('bakery', 'Food & dining', SpendCategoryKind.food),
    ('hotel', 'Food & dining', SpendCategoryKind.food),

    // Quick commerce & groceries
    ('blinkit', 'Groceries', SpendCategoryKind.groceries),
    ('zepto', 'Groceries', SpendCategoryKind.groceries),
    ('instamart', 'Groceries', SpendCategoryKind.groceries),
    ('bigbasket', 'Groceries', SpendCategoryKind.groceries),
    ('big basket', 'Groceries', SpendCategoryKind.groceries),
    ('jiomart', 'Groceries', SpendCategoryKind.groceries),
    ('dmart', 'Groceries', SpendCategoryKind.groceries),
    ('d mart', 'Groceries', SpendCategoryKind.groceries),
    ('reliance fresh', 'Groceries', SpendCategoryKind.groceries),
    ('more retail', 'Groceries', SpendCategoryKind.groceries),
    ('spencers', 'Groceries', SpendCategoryKind.groceries),
    ('licious', 'Groceries', SpendCategoryKind.groceries),
    ('country delight', 'Groceries', SpendCategoryKind.groceries),
    ('milkbasket', 'Groceries', SpendCategoryKind.groceries),
    ('grofers', 'Groceries', SpendCategoryKind.groceries),
    ('supermarket', 'Groceries', SpendCategoryKind.groceries),
    ('grocery', 'Groceries', SpendCategoryKind.groceries),

    // Transport
    ('uber', 'Transport', SpendCategoryKind.transport),
    ('ola', 'Transport', SpendCategoryKind.transport),
    ('rapido', 'Transport', SpendCategoryKind.transport),
    ('namma yatri', 'Transport', SpendCategoryKind.transport),
    ('blusmart', 'Transport', SpendCategoryKind.transport),
    ('blu smart', 'Transport', SpendCategoryKind.transport),
    ('metro', 'Transport', SpendCategoryKind.transport),
    ('dmrc', 'Transport', SpendCategoryKind.transport),
    ('bmrcl', 'Transport', SpendCategoryKind.transport),
    ('irctc', 'Travel', SpendCategoryKind.travel),
    ('indigo', 'Travel', SpendCategoryKind.travel),
    ('air india', 'Travel', SpendCategoryKind.travel),
    ('vistara', 'Travel', SpendCategoryKind.travel),
    ('spicejet', 'Travel', SpendCategoryKind.travel),
    ('akasa', 'Travel', SpendCategoryKind.travel),
    ('makemytrip', 'Travel', SpendCategoryKind.travel),
    ('goibibo', 'Travel', SpendCategoryKind.travel),
    ('cleartrip', 'Travel', SpendCategoryKind.travel),
    ('ixigo', 'Travel', SpendCategoryKind.travel),
    ('oyo', 'Travel', SpendCategoryKind.travel),
    ('redbus', 'Travel', SpendCategoryKind.travel),
    ('parking', 'Transport', SpendCategoryKind.transport),
    ('fastag', 'Transport', SpendCategoryKind.transport),

    // Fuel
    ('petrol', 'Fuel', SpendCategoryKind.fuel),
    ('diesel', 'Fuel', SpendCategoryKind.fuel),
    ('indian oil', 'Fuel', SpendCategoryKind.fuel),
    // `INF*Indian` is the Infibeam tag in front of an Indian Oil pump.
    ('inf indian', 'Fuel', SpendCategoryKind.fuel),
    ('iocl', 'Fuel', SpendCategoryKind.fuel),
    ('hp petrol', 'Fuel', SpendCategoryKind.fuel),
    ('hpcl', 'Fuel', SpendCategoryKind.fuel),
    ('bharat petroleum', 'Fuel', SpendCategoryKind.fuel),
    ('bpcl', 'Fuel', SpendCategoryKind.fuel),
    ('shell', 'Fuel', SpendCategoryKind.fuel),
    ('reliance petro', 'Fuel', SpendCategoryKind.fuel),
    ('nayara', 'Fuel', SpendCategoryKind.fuel),
    ('cng', 'Fuel', SpendCategoryKind.fuel),

    // Shopping
    ('amazon', 'Shopping', SpendCategoryKind.shopping),
    ('flipkart', 'Shopping', SpendCategoryKind.shopping),
    // `PYU*Flipkar` — PayU tag plus a truncated brand.
    ('flipkar', 'Shopping', SpendCategoryKind.shopping),
    ('myntra', 'Shopping', SpendCategoryKind.shopping),
    ('ajio', 'Shopping', SpendCategoryKind.shopping),
    ('nykaa', 'Shopping', SpendCategoryKind.shopping),
    ('meesho', 'Shopping', SpendCategoryKind.shopping),
    ('tatacliq', 'Shopping', SpendCategoryKind.shopping),
    ('snapdeal', 'Shopping', SpendCategoryKind.shopping),
    ('decathlon', 'Shopping', SpendCategoryKind.shopping),
    ('ikea', 'Shopping', SpendCategoryKind.shopping),
    ('croma', 'Shopping', SpendCategoryKind.shopping),
    ('reliance digital', 'Shopping', SpendCategoryKind.shopping),
    ('vijay sales', 'Shopping', SpendCategoryKind.shopping),
    ('lifestyle', 'Shopping', SpendCategoryKind.shopping),
    ('shoppers stop', 'Shopping', SpendCategoryKind.shopping),
    ('westside', 'Shopping', SpendCategoryKind.shopping),
    ('zara', 'Shopping', SpendCategoryKind.shopping),
    ('h&m', 'Shopping', SpendCategoryKind.shopping),
    ('uniqlo', 'Shopping', SpendCategoryKind.shopping),
    ('firstcry', 'Shopping', SpendCategoryKind.shopping),
    ('lenskart', 'Shopping', SpendCategoryKind.shopping),
    ('titan', 'Shopping', SpendCategoryKind.shopping),
    ('tanishq', 'Shopping', SpendCategoryKind.shopping),

    // Bills & utilities
    ('airtel', 'Bills & utilities', SpendCategoryKind.bills),
    ('jio', 'Bills & utilities', SpendCategoryKind.bills),
    ('vodafone', 'Bills & utilities', SpendCategoryKind.bills),
    ('vi recharge', 'Bills & utilities', SpendCategoryKind.bills),
    ('bsnl', 'Bills & utilities', SpendCategoryKind.bills),
    ('act fibernet', 'Bills & utilities', SpendCategoryKind.bills),
    ('hathway', 'Bills & utilities', SpendCategoryKind.bills),
    ('broadband', 'Bills & utilities', SpendCategoryKind.bills),
    ('electricity', 'Bills & utilities', SpendCategoryKind.bills),
    ('bescom', 'Bills & utilities', SpendCategoryKind.bills),
    ('mseb', 'Bills & utilities', SpendCategoryKind.bills),
    ('tata power', 'Bills & utilities', SpendCategoryKind.bills),
    ('adani electricity', 'Bills & utilities', SpendCategoryKind.bills),
    ('gas bill', 'Bills & utilities', SpendCategoryKind.bills),
    ('indane', 'Bills & utilities', SpendCategoryKind.bills),
    ('hp gas', 'Bills & utilities', SpendCategoryKind.bills),
    ('water bill', 'Bills & utilities', SpendCategoryKind.bills),
    ('bwssb', 'Bills & utilities', SpendCategoryKind.bills),
    ('insurance', 'Bills & utilities', SpendCategoryKind.bills),
    ('lic', 'Bills & utilities', SpendCategoryKind.bills),
    ('policybazaar', 'Bills & utilities', SpendCategoryKind.bills),

    // Rent
    ('rent', 'Rent', SpendCategoryKind.rent),
    ('nobroker', 'Rent', SpendCategoryKind.rent),
    ('housing', 'Rent', SpendCategoryKind.rent),
    ('mygate', 'Rent', SpendCategoryKind.rent),
    ('society', 'Rent', SpendCategoryKind.rent),
    ('maintenance', 'Rent', SpendCategoryKind.rent),

    // Entertainment & subscriptions
    ('netflix', 'Entertainment', SpendCategoryKind.entertainment),
    ('spotify', 'Entertainment', SpendCategoryKind.entertainment),
    ('hotstar', 'Entertainment', SpendCategoryKind.entertainment),
    ('disney', 'Entertainment', SpendCategoryKind.entertainment),
    ('prime video', 'Entertainment', SpendCategoryKind.entertainment),
    ('sonyliv', 'Entertainment', SpendCategoryKind.entertainment),
    ('zee5', 'Entertainment', SpendCategoryKind.entertainment),
    ('jiocinema', 'Entertainment', SpendCategoryKind.entertainment),
    ('youtube', 'Entertainment', SpendCategoryKind.entertainment),
    ('bookmyshow', 'Entertainment', SpendCategoryKind.entertainment),
    ('pvr', 'Entertainment', SpendCategoryKind.entertainment),
    ('inox', 'Entertainment', SpendCategoryKind.entertainment),
    ('steam', 'Entertainment', SpendCategoryKind.entertainment),
    ('google play', 'Entertainment', SpendCategoryKind.entertainment),
    ('apple', 'Entertainment', SpendCategoryKind.entertainment),
    ('subscription', 'Entertainment', SpendCategoryKind.entertainment),

    // Health
    ('apollo', 'Health', SpendCategoryKind.health),
    ('pharmeasy', 'Health', SpendCategoryKind.health),
    ('1mg', 'Health', SpendCategoryKind.health),
    ('netmeds', 'Health', SpendCategoryKind.health),
    ('practo', 'Health', SpendCategoryKind.health),
    ('cult', 'Health', SpendCategoryKind.health),
    ('cure fit', 'Health', SpendCategoryKind.health),
    ('cultfit', 'Health', SpendCategoryKind.health),
    ('gym', 'Health', SpendCategoryKind.health),
    ('hospital', 'Health', SpendCategoryKind.health),
    ('clinic', 'Health', SpendCategoryKind.health),
    ('pharmacy', 'Health', SpendCategoryKind.health),
    ('diagnostic', 'Health', SpendCategoryKind.health),
    ('lab', 'Health', SpendCategoryKind.health),

    // Education
    ('udemy', 'Education', SpendCategoryKind.education),
    ('coursera', 'Education', SpendCategoryKind.education),
    ('byju', 'Education', SpendCategoryKind.education),
    ('unacademy', 'Education', SpendCategoryKind.education),
    ('school fee', 'Education', SpendCategoryKind.education),
    ('college', 'Education', SpendCategoryKind.education),
    ('tuition', 'Education', SpendCategoryKind.education),
    ('university', 'Education', SpendCategoryKind.education),

    // Investments
    ('zerodha', 'Investments', SpendCategoryKind.investments),
    ('groww', 'Investments', SpendCategoryKind.investments),
    ('upstox', 'Investments', SpendCategoryKind.investments),
    ('kuvera', 'Investments', SpendCategoryKind.investments),
    ('coin', 'Investments', SpendCategoryKind.investments),
    ('mutual fund', 'Investments', SpendCategoryKind.investments),
    ('sip', 'Investments', SpendCategoryKind.investments),
    ('indmoney', 'Investments', SpendCategoryKind.investments),
    ('smallcase', 'Investments', SpendCategoryKind.investments),
  ];

  ({String name, SpendCategoryKind kind}) categorize(String? merchant, {
    TxnKind? kind,
    TransferReason? transferReason,
  }) {
    if (kind == TxnKind.income) {
      return (name: 'Income', kind: SpendCategoryKind.income);
    }
    if (kind == TxnKind.cash) {
      return (name: 'Cash', kind: SpendCategoryKind.cash);
    }
    if (kind == TxnKind.transfer) {
      // A SIP, a mandate to a fund house, an FD: money put to work is
      // "Investments", not a generic transfer (the owner had to fix a
      // WhiteOak Capital SIP by hand).
      if (transferReason == TransferReason.investment ||
          transferReason == TransferReason.redemption) {
        return (name: 'Investments', kind: SpendCategoryKind.investments);
      }
      return (name: 'Transfers', kind: SpendCategoryKind.transfers);
    }
    final normalised = _normalise(merchant ?? '');
    if (normalised.isEmpty) {
      return (name: 'Other', kind: SpendCategoryKind.other);
    }
    for (final rule in _rules) {
      if (normalised.contains(rule.$1)) {
        return (name: rule.$2, kind: rule.$3);
      }
    }
    // The same shop must be recognised next time even when the alert adds a
    // store number or a branch: `Pluxee Meal 4411` and `Pluxee-Mcal` share the
    // normalised merchant signature, so a rule learned on one fires on the
    // other. Learned `merchant_rules` are consulted before this fallback by the
    // repository; this is the bundled-rule equivalent.
    final signature = MerchantSignature.of(merchant);
    if (signature != null && signature != normalised) {
      for (final rule in _rules) {
        if (signature.contains(rule.$1)) {
          return (name: rule.$2, kind: rule.$3);
        }
      }
    }
    return (name: 'Other', kind: SpendCategoryKind.other);
  }

  static String _normalise(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9&]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
