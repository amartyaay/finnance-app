// Throwaway reviewer probe #2: scroll the *vertical* lists (the first probe
// caught the horizontal chip row) and dump the copy that Activity/Insights
// actually render, so I can check the money strings on the VM.
import 'package:finnance_app/app.dart';
import 'package:finnance_app/data/demo_repository.dart';
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

  List<String> texts(WidgetTester tester) {
    final out = <String>[];
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final t = w.data ?? w.textSpan?.toPlainText();
      if (t != null && t.trim().isNotEmpty) out.add(t);
    }
    return out;
  }

  testWidgets('vertical lists scroll clean at 360x800 @1.3x', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repo = DemoFinanceRepository(now: _now);
    final state = AppState(
      repository: repo,
      permissions: const _Granted(),
      now: () => _now,
    );
    await tester.pumpWidget(FinanceApp(appState: state, autoInitialize: true));
    await tester.pumpAndSettle();
    final errors = <Object>[];
    void drain() {
      final e = tester.takeException();
      if (e != null) errors.add(e);
    }

    drain();
    final navBar = find.byType(NavigationBar);
    final seen = <String, int>{};
    for (final tab in <String>['Activity', 'Cards', 'Insights']) {
      await tester.tap(find.descendant(of: navBar, matching: find.text(tab)));
      await tester.pumpAndSettle();
      drain();
      // Drag the vertical list explicitly (first ListView in the tree).
      final list = find.byType(ListView).first;
      for (var i = 0; i < 14; i++) {
        await tester.drag(list, const Offset(0, -420));
        await tester.pumpAndSettle();
        drain();
        seen[tab] = i;
      }
      // ignore: avoid_print
      print('TEXTS $tab: ${texts(tester).join(' | ')}');
    }
    // ignore: avoid_print
    print('DRAWS: $seen');
    // ignore: avoid_print
    print('ERRORS: ${errors.map((e) => e.toString().split('\n').first).toList()}');
    expect(errors, isEmpty, reason: errors.map((e) => e.toString()).join('\n'));
  });
}
