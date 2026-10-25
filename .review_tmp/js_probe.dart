// Throwaway: run the same pure-Dart path under dart2js/node to see whether the
// web compiler reproduces the "0%" ring / "₹0 outstanding" seen in the web shots.
import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/domain/money.dart';

Future<void> main() async {
  final repo = DemoFinanceRepository(now: DateTime(2026, 10, 25, 21, 47));
  final data = await repo.load();
  print('totalUtilization=${data.totalUtilization}');
  for (final c in data.cards) {
    print('${c.card.last4}: outstanding=${c.outstandingPaise} '
        '(${inr(c.outstanding)}) cycle=${c.spentThisCyclePaise} '
        '(${inr(c.spentThisCycle)}) util=${c.utilization} band=${c.band.name} '
        'limit=${c.card.creditLimitPaise}');
  }
}
