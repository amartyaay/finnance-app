// Prints exactly what the Cards screen receives, using the same demo repository
// the web build uses. Run: dart run tool/cards_check.dart
import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/domain/money.dart';

Future<void> main() async {
  final repo = DemoFinanceRepository();
  final data = await repo.load();
  print('now=${DateTime.now()}');
  print('totalUtilization=${data.totalUtilization}');
  for (final card in data.cards) {
    print('${card.card.title}');
    print('  outstanding=${inr(card.outstanding)} limit=${inr(card.limit)} '
        'util=${card.utilization} band=${card.band.name}');
    print('  thisCycle=${inr(card.spentThisCycle)} lastCycle=${inr(card.spentLastCycle)} '
        'txns=${card.txnCount}');
    print('  totalDue=${inr(card.totalDue)} minDue=${card.minimumDue} '
        'due=${card.dueDate} daysToDue=${card.daysToDue} statement=${card.statementDate} '
        'daysToStatement=${card.daysToStatement}');
    print('  available=${card.availableLimit} projected=${card.projectedUtilization}');
  }
}
