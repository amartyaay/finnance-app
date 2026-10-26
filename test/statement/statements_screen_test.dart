// The salary & statements screens at the 360 dp / 1.3x layout bar, light and
// dark, empty and full, scrolled to the end — the same gate as
// test/layout_overflow_test.dart, for the screens added with statement import.
import 'package:finnance_app/app/theme.dart';
import 'package:finnance_app/data/statement_store.dart';
import 'package:finnance_app/domain/statement.dart';
import 'package:finnance_app/services/statement/statement_importer.dart';
import 'package:finnance_app/services/statement/statement_words.dart';
import 'package:finnance_app/state/statements_controller.dart';
import 'package:finnance_app/views/salary_cycle_screen.dart';
import 'package:finnance_app/views/statements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fixtures/sbi_statements.dart';

/// A controller with the parsed layout-B statement and no database.
class _StubController extends StatementsController {
  _StubController({required this.empty});

  final bool empty;
  late final List<StatementRow> _stubRows = const StatementImporter()
      .parse(wordsFromText(sbiLayoutB))
      .rows;

  @override
  Future<void> load() async {}

  @override
  bool get hasLoaded => true;

  @override
  List<StatementAccount> get accounts => empty
      ? const []
      : [
          StatementAccount(
            accountKey: 'SBI:7890',
            bank: 'SBI',
            accountMask: '7890',
            holderName: 'RAHUL VERMA',
            from: DateTime(2026, 9, 1),
            to: DateTime(2026, 10, 1),
            files: 1,
            rows: _stubRows.length,
            verified: _stubRows.length,
          ),
        ];

  @override
  StatementAccount? get selected => accounts.firstOrNull;

  @override
  List<StatementRow> get rows => empty ? const [] : _stubRows;

  @override
  StatementAnalysis? get analysis =>
      empty ? null : const StatementImporter().analyse(_stubRows);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool empty,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<StatementsController>.value(
      value: _StubController(empty: empty),
      child: MaterialApp(
        theme: buildAppTheme(brightness: brightness),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('empty statements screen fits 360dp @1.3x (${brightness.name})', (tester) async {
      await _pump(tester, const StatementsScreen(), empty: true, brightness: brightness);
      expect(find.text('Choose statement PDF'), findsOneWidget);
      await _scrollToEnd(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('statements with cycles fit 360dp @1.3x (${brightness.name})', (tester) async {
      await _pump(tester, const StatementsScreen(), empty: false, brightness: brightness);
      expect(find.textContaining('Salary ₹1,12,450'), findsOneWidget);
      // Newest cycle first: the one still running.
      expect(find.text('Left so far'), findsOneWidget);
      await _scrollToEnd(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cycle detail fits 360dp @1.3x (${brightness.name})', (tester) async {
      await _pump(
        tester,
        SalaryCycleScreen(start: DateTime(2026, 9, 1)),
        empty: false,
        brightness: brightness,
      );
      expect(find.text('In and out'), findsOneWidget);
      expect(find.text('Saved this cycle'), findsOneWidget);
      await _scrollToEnd(tester);
      expect(find.textContaining('ACME SOFTWARE'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
