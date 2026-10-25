// The 360 dp layout guard: every screen the app ships, at the small-phone width
// and the large-text accessibility setting, scrolled to the end of every list,
// with zero Flutter errors (an overflow paints a yellow/black bar and throws).
//
// Why this file exists: the round-2 review applied an **automatic fail** for a
// 63 px overflow on Insights at 360x800 @1.3x. The suite was green the whole
// time, because `widget_smoke_test.dart` only ever pumped Home and Cards, at the
// top of the list, in light mode. A layout gate that never visits a screen is not
// a layout gate. This one visits all six screens in both themes and at two text
// scales, and it visits them where overflow actually appears: at the end of the
// scroll, where the last chip, legend row or due date lives.
//
// Flutter errors (including RenderFlex overflow) are drained after each step
// instead of aborting on the first frame, so one run reports every broken anchor
// on a screen rather than only the first.

import 'package:finnance_app/app.dart';
import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/data/finance_repository.dart';
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/merchant_rule.dart';
import 'package:finnance_app/engine/card_metrics.dart';
import 'package:finnance_app/services/sms_reader.dart';
import 'package:finnance_app/state/app_state.dart';
import 'package:finnance_app/viewmodels/theme_view_model.dart';
import 'package:finnance_app/views/widgets/card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SMS permission granted: these tests must reach the dashboard, not onboarding.
class _GrantedGate implements SmsPermissionGate {
  const _GrantedGate();

  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;

  @override
  Future<void> openSettings() async {}
}

/// A repository with nothing in it, so the empty states are exercised for real
/// rather than by stubbing a widget.
class _EmptyRepository implements FinanceRepository {
  _EmptyRepository(this._now);

  final DateTime _now;

  @override
  bool get isDemo => false;

  @override
  Future<HomeData> load() async => HomeData.empty(_now);

  @override
  Future<IngestResult> ingest() async => IngestResult.none;

  @override
  Future<IngestResult> reparseAll() async => IngestResult.none;

  @override
  Future<void> deleteCard(String issuer, String last4) async {}

  @override
  Future<void> assignCategory({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  }) async {}

  @override
  Future<void> excludeTxn(String txnKey) async {}

  @override
  Future<List<MerchantRule>> merchantRules() async => const [];

  @override
  Future<void> forgetMerchantRule(String signature) async {}

  @override
  Future<void> saveCard(CardAccount card) async {}

  @override
  Future<void> dismissInsight(String id) async {}

  @override
  Future<void> startDemo() async {}

  @override
  Future<void> exitDemo() async {}

  @override
  Future<void> clearAll() async {}
}

/// One fixed instant so the demo ledger and its due dates are deterministic.
final DateTime _fixedNow = DateTime(2026, 6, 15, 12);

/// Collects every Flutter error instead of letting the first one abort the run,
/// so a single test reports all the overflow anchors on a screen.
class _LayoutHarness {
  _LayoutHarness(this.tester);

  final WidgetTester tester;
  final List<String> errors = <String>[];

  void drain() {
    final error = tester.takeException();
    if (error != null) errors.add(error.toString());
  }

  String get summary => errors.join('\n---\n');
}

Future<_LayoutHarness> _pumpApp(
  WidgetTester tester, {
  required double textScale,
  required AppThemePreference theme,
  FinanceRepository? repository,
  Size surface = const Size(360, 800),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final FinanceRepository repo = repository ?? DemoFinanceRepository(now: _fixedNow);
  final state = AppState(
    repository: repo,
    permissions: const _GrantedGate(),
    now: () => _fixedNow,
  );

  await tester.pumpWidget(
    FinanceApp(
      appState: state,
      themeViewModel: ThemeViewModel(initialPreference: theme),
      autoInitialize: true,
    ),
  );
  await tester.pumpAndSettle();

  final harness = _LayoutHarness(tester);
  harness.drain();
  return harness;
}

/// The vertical scroller of the current screen. Charts and chip strips nest
/// horizontal scrollers inside it, so pick by axis instead of by index.
Finder _verticalScrollView() => find
    .byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

/// Drag to the end of the current screen's main list, draining errors after
/// every step so the failing frame is reported with its screen name.
Future<void> _scrollToEnd(WidgetTester tester, _LayoutHarness harness) async {
  const maxSteps = 24;
  for (var step = 0; step < maxSteps; step++) {
    final finder = _verticalScrollView();
    if (finder.evaluate().isEmpty) break;
    final position = tester.state<ScrollableState>(finder).position;
    if (position.pixels >= position.maxScrollExtent - 0.5) break;
    await tester.drag(finder, const Offset(0, -280));
    await tester.pump(const Duration(milliseconds: 90));
    harness.drain();
  }
  // Let entrance animations, chart draws and the last relayout finish.
  await tester.pump(const Duration(milliseconds: 500));
  harness.drain();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  final navBar = find.byType(NavigationBar);
  await tester.tap(find.descendant(of: navBar, matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// A named screen plus the navigation needed to reach it from a fresh launch.
class _Screen {
  const _Screen({required this.name, required this.open, required this.anchor});

  final String name;
  final Future<void> Function(WidgetTester tester) open;

  /// Something that must be on the screen, so a blank or failed screen cannot
  /// pass the overflow check by rendering nothing.
  final Finder anchor;
}

final List<_Screen> _screens = [
  _Screen(
    name: 'Home',
    open: (tester) async {},
    anchor: find.text('Spent this month'),
  ),
  _Screen(
    name: 'Activity',
    open: (tester) async => _tapTab(tester, 'Activity'),
    anchor: find.byType(RefreshIndicator),
  ),
  _Screen(
    name: 'Cards',
    open: (tester) async => _tapTab(tester, 'Cards'),
    anchor: find.byType(CardFace),
  ),
  _Screen(
    name: 'Insights',
    open: (tester) async => _tapTab(tester, 'Insights'),
    anchor: find.text('Needs attention'),
  ),
  _Screen(
    name: 'Settings',
    open: (tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    },
    anchor: find.text('Scan SMS inbox'),
  ),
  _Screen(
    name: 'All messages',
    open: (tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('All messages'),
        160,
        scrollable: _verticalScrollView(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All messages'));
      await tester.pumpAndSettle();
    },
    anchor: find.byType(TextField),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final config in const [
    (label: '1.3x light', scale: 1.3, theme: AppThemePreference.light),
    (label: '1.3x dark', scale: 1.3, theme: AppThemePreference.dark),
    (label: '1.0x light', scale: 1.0, theme: AppThemePreference.light),
  ]) {
    for (final screen in _screens) {
      testWidgets(
        '${screen.name} lays out without overflow at 360x800, ${config.label}',
        (tester) async {
          final harness = await _pumpApp(
            tester,
            textScale: config.scale,
            theme: config.theme,
          );
          await screen.open(tester);
          harness.drain();

          expect(
            screen.anchor,
            findsWidgets,
            reason: '${screen.name} did not render, so the overflow check would '
                'be vacuous.',
          );

          await _scrollToEnd(tester, harness);

          expect(
            harness.errors,
            isEmpty,
            reason:
                '${screen.name} threw at 360x800, ${config.label} while scrolling '
                'to the end:\n${harness.summary}',
          );
        },
      );
    }
  }

  // The two states a green suite never visits: an app with no data at all, and
  // the All-messages screen with no inbox behind it.
  testWidgets('empty app lays out without overflow on every tab', (tester) async {
    final harness = await _pumpApp(
      tester,
      textScale: 1.3,
      theme: AppThemePreference.light,
      repository: _EmptyRepository(_fixedNow),
    );

    expect(find.text('No transactions yet'), findsOneWidget);
    await _scrollToEnd(tester, harness);

    await _tapTab(tester, 'Activity');
    expect(find.text('No transactions yet'), findsWidgets);
    await _scrollToEnd(tester, harness);

    await _tapTab(tester, 'Cards');
    expect(find.text('No cards found yet'), findsOneWidget);
    await _scrollToEnd(tester, harness);

    await _tapTab(tester, 'Insights');
    expect(find.text('Nothing to analyse yet'), findsOneWidget);
    await _scrollToEnd(tester, harness);

    expect(
      harness.errors,
      isEmpty,
      reason: 'An empty account threw at 360x800 @1.3x:\n${harness.summary}',
    );
  });

  testWidgets('All messages without an inbox lays out without overflow', (tester) async {
    final harness = await _pumpApp(
      tester,
      textScale: 1.3,
      theme: AppThemePreference.dark,
      repository: _EmptyRepository(_fixedNow),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('All messages'),
      160,
      scrollable: _verticalScrollView(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All messages'));
    await tester.pumpAndSettle();
    harness.drain();

    expect(find.text('Messages stay on this phone'), findsOneWidget);
    await _scrollToEnd(tester, harness);

    expect(
      harness.errors,
      isEmpty,
      reason: 'The no-inbox empty state threw at 360x800 @1.3x:\n'
          '${harness.summary}',
    );
  });
}
