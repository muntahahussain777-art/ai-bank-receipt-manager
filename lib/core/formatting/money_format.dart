import 'package:intl/intl.dart';

String formatPkr(num amount) {
  final whole = amount == amount.roundToDouble();
  return NumberFormat.currency(
    locale: 'en_US',
    symbol: 'Rs ',
    decimalDigits: whole ? 0 : 2,
  ).format(amount);
}

String formatCount(int value) {
  return NumberFormat.decimalPattern('en_US').format(value);
}
