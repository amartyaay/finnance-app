import 'package:intl/intl.dart';

String formatInrFromPaise(int paise) {
  final amount = paise / 100.0;
  final decimalDigits = paise % 100 == 0 ? 0 : 2;
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: decimalDigits,
  ).format(amount);
}

String formatScanTime(DateTime? time) {
  if (time == null) {
    return 'Not scanned yet';
  }
  return DateFormat('d MMM, h:mm a').format(time);
}
