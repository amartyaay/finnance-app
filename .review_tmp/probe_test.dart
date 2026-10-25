// Throwaway reviewer probe. Not part of the repo; deleted after the review.
// Pumps the real app at several surfaces, dumps rendered text, captures goldens
// at 360x800 @1.3x (the mandated layout case with no existing screenshot).
import 'package:finnance_app/app.dart';
import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/domain/money.dart';
import 'package:finnance_app/services/sms_reader.dart';
import 'package:finnance_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Granted implements SmsPermissionGate {
  const _Granted();
  @override
  Future<bool> isGranted() async => true;
  @override
  Future<bool> request() async => true;
  @override
  Future<void> openSettings() async {}
}

final DateTime _now = DateTime(2026, 10, 25, 21, 47);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<List<String>> pump(
    WidgetTester tester, {
    required Size size,
    required double scale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repo = DemoFinanceRepository(now: _now);
    final data = await repo.load();
    final state = AppState(
      repository: repo,
      permissions: const _Granted(),
      now: () => _now,
    );
    await tester.pumpWidget(FinanceApp(appState: state, autoInitialize: true));
    await tester.pumpAndSettle();
    return <String>[
      'HDFC outstanding=${inr(data.cards.first.outstanding)} '
          'util=${data.cards.first.utilization} '
          'totalUtil=${data.totalUtilization}',
    ];
  }

  List<String> texts(WidgetTester tester) {
    final out = <String>[];
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final t = w.data ?? w.textSpan?.toPlainText();
      if (t != null && t.trim().isNotEmpty) out.add(t);
    }
    return out;
  }

  for (final cfg in <({String name, Size size, double scale})>[
    (name: '360x800_1.3x', size: const Size(360, 800), scale: 1.3),
    (name: '412x915_1.0x', size: const Size(412, 915), scale: 1.0),
  ]) {
    testWidgets('all tabs scroll clean at ${cfg.name}', (tester) async {
      final facts = await pump(tester, size: cfg.size, scale: cfg.scale);
      final errors = <Object>[];
      void drain() {
        final e = tester.takeException();
        if (e != null) errors.add(e);
      }

      drain();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_top_${cfg.name}.png'),
      );

      // Home: scroll to the very bottom so Cards strip / insights / recent /
      // footer are actually laid out.
      final homeScroll = find.byType(Scrollable).first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(homeScroll, Offset(0, -400));
        await tester.pumpAndSettle();
        drain();
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_bottom_${cfg.name}.png'),
      );

      final navBar = find.byType(NavigationBar);
      for (final tab in <({int index, String label})>[
        (index: 1, label: 'Activity'),
        (index: 2, label: 'Cards'),
        (index: 3, label: 'Insights'),
      ]) {
        await tester.tap(find.descendant(of: navBar, matching: find.text(tab.label)));
        await tester.pumpAndSettle();
        drain();
        if (tab.index == 2) {
          // ignore: avoid_print
          print('CARDS TEXTS: ${texts(tester).join(' | ')}');
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${tab.label.toLowerCase()}_top_${cfg.name}.png'),
        );
        final scrollable = find.byType(Scrollable).last;
        for (var i = 0; i < 10; i++) {
          await tester.drag(scrollable, Offset(0, -400));
          await tester.pumpAndSettle();
          drain();
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${tab.label.toLowerCase()}_bottom_${cfg.name}.png'),
        );
      }

      // ignore: avoid_print
      print('FACTS ${cfg.name}: ${facts.join('; ')}');
      // ignore: avoid_print
      print('ERRORS ${cfg.name}: ${errors.map((e) => e.toString().split('\n').first).toList()}');
      expect(errors, isEmpty, reason: errors.map((e) => e.toString()).join('\n'));
    });
  }
}
