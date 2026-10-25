// Throwaway probe: what does Home throw at 360x800 @1.3x?
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('home probe', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final fixedNow = DateTime(2026, 6, 15, 12);
    final repo = DemoFinanceRepository(now: fixedNow);
    final data = await repo.load();
    final state = AppState(
      repository: repo,
      permissions: const _Granted(),
      now: () => fixedNow,
    );
    await tester.pumpWidget(FinanceApp(appState: state));
    await tester.pumpAndSettle();

    final errors = <Object>[];
    Object? e;
    while ((e = tester.takeException()) != null) {
      errors.add(e!);
    }
    // ignore: avoid_print
    print('SPEND=${data.summary.spend} hasIncome=${data.hasTrueIncome}');
    // ignore: avoid_print
    print('FIND=${find.text('₹1,17,801.26').evaluate().length}');
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final plain = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (plain.startsWith('₹') || plain.contains('Spent')) {
        // ignore: avoid_print
        print('TEXT="$plain"');
      }
    }
    // ignore: avoid_print
    print('ERRORS=${errors.length}');
    for (final error in errors) {
      // ignore: avoid_print
      print(error.toString().split('\n').take(12).join('\n'));
    }
    expect(errors, isEmpty);
  });
}
