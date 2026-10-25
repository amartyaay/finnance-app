// Widget smoke test: the real app, demo data, a small phone and large text.
//
// The task brief asked for `HomeScreen` only if the Cards / Activity / Insights
// screens did not exist yet. They now do (`lib/views/*_screen.dart`) and `lib/`
// analyzes clean, so this test pumps the full `FinanceApp` and exercises the
// real four-tab shell.
//
// Surface: 360x800 logical pixels (the small-phone case the design targets) with
// the platform text scale at 1.3. `FinanceApp` owns its `MaterialApp`, so the
// text scale has to be applied at the platform-dispatcher level: that is what
// feeds the `MediaQuery` the app creates, and is equivalent to wrapping the app
// in `MediaQuery(data: ...copyWith(textScaler: TextScaler.linear(1.3)))`.
//
// Flutter errors (including RenderFlex overflow) are drained after each step
// instead of aborting on the first frame, so one run reports every broken
// anchor. The test still fails if any error is thrown: `errors` must be empty.

import 'package:finnance_app/app.dart';
import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/data/finance_repository.dart';
import 'package:finnance_app/domain/money.dart';
import 'package:finnance_app/services/sms_reader.dart';
import 'package:finnance_app/state/app_state.dart';
import 'package:finnance_app/views/cards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SMS permission granted: the smoke test must reach the dashboard, not
/// onboarding.
class _GrantedGate implements SmsPermissionGate {
  const _GrantedGate();

  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;

  @override
  Future<void> openSettings() async {}
}

/// One fixed instant so the demo ledger, statement cycles and month labels are
/// deterministic.
final DateTime _fixedNow = DateTime(2026, 6, 15, 12);

class _Harness {
  _Harness(this.data);

  final HomeData data;
  final List<Object> errors = <Object>[];

  /// Take (and keep) any Flutter error reported since the last drain. This is
  /// the supported way to assert "no exception/overflow" while still letting the
  /// test continue past a known failure.
  void drain(WidgetTester tester) {
    final error = tester.takeException();
    if (error != null) errors.add(error);
  }

  String get errorSummary => errors.map((e) => e.toString()).join('\n');
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required Size surface,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final repository = DemoFinanceRepository(now: _fixedNow);
  final data = await repository.load();
  final state = AppState(
    repository: repository,
    permissions: const _GrantedGate(),
    now: () => _fixedNow,
  );

  await tester.pumpWidget(
    FinanceApp(appState: state, autoInitialize: true),
  );
  await tester.pumpAndSettle();

  final harness = _Harness(data);
  harness.drain(tester);
  return harness;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ThemeViewModel reads the theme preference through SharedPreferences; the
    // in-memory mock keeps the test free of plugins.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const surface = Size(360, 800);

  testWidgets('home shows the hero amount and category rows', (tester) async {
    final harness = await _pumpApp(tester, surface: surface);
    final data = harness.data;

    expect(data.summary.spendPaise, greaterThan(0));
    expect(data.summary.byCategory, isNotEmpty);

    // The hero renders the exact Indian-grouped amount (MoneyText, no animation).
    expect(find.text(inr(data.summary.spend)), findsOneWidget);

    // The category card is below the hero; scroll it into view if needed.
    await tester.scrollUntilVisible(
      find.text('Where it went'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    harness.drain(tester);

    expect(find.text('Where it went'), findsOneWidget);
    expect(find.text(data.summary.byCategory.first.name), findsWidgets);

    expect(
      harness.errors,
      isEmpty,
      reason: 'Flutter errors at 360x800 @1.3x:\n${harness.errorSummary}',
    );
  });

  testWidgets('Cards destination renders a card', (tester) async {
    final harness = await _pumpApp(tester, surface: surface);
    final data = harness.data;

    expect(data.cards, isNotEmpty);
    final firstCard = data.cards.first.card;

    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);

    await tester.tap(
      find.descendant(of: navBar, matching: find.text('Cards')),
    );
    await tester.pumpAndSettle();
    harness.drain(tester);

    expect(tester.widget<NavigationBar>(navBar).selectedIndex, 2);

    // The Cards screen itself renders the card's display name and masked tail.
    final cardsScreen = find.byType(CardsScreen);
    expect(cardsScreen, findsOneWidget);
    expect(
      find.descendant(
        of: cardsScreen,
        matching: find.text(firstCard.displayName),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: cardsScreen,
        matching: find.textContaining(firstCard.masked),
      ),
      findsWidgets,
    );

    expect(
      harness.errors,
      isEmpty,
      reason: 'Flutter errors at 360x800 @1.3x:\n${harness.errorSummary}',
    );
  });
}
