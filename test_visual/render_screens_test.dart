// Renders the app's screens to PNG on the host, with the real bundled fonts,
// so the UI can be reviewed without a phone:
//
//   flutter test test_visual/render_screens_test.dart
//
// Output: docs/shots/render-<screen>-<theme>.png (412x915 dp, the S24's
// logical size, at 2x). Demo data at a fixed instant, so renders are stable.
// Not part of `flutter test` (lives outside test/): it is a viewing tool.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finnance_app/app.dart';
import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/data/statement_store.dart';
import 'package:finnance_app/domain/statement.dart';
import 'package:finnance_app/services/statement/statement_importer.dart';
import 'package:finnance_app/services/statement/statement_words.dart';
import 'package:finnance_app/services/sms_reader.dart';
import 'package:finnance_app/state/app_state.dart';
import 'package:finnance_app/state/statements_controller.dart';
import 'package:finnance_app/viewmodels/theme_view_model.dart';
import 'package:finnance_app/views/onboarding_screen.dart';
import 'package:finnance_app/views/salary_cycle_screen.dart';
import 'package:finnance_app/views/settings_screen.dart';
import 'package:finnance_app/views/statements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/fixtures/sbi_statements.dart';

final DateTime _now = DateTime(2026, 6, 15, 12);

class _Granted implements SmsPermissionGate {
  const _Granted();
  @override
  Future<bool> isGranted() async => true;
  @override
  Future<bool> request() async => true;
  @override
  Future<void> openSettings() async {}
}

/// Statements from the synthetic layout-B fixture, without a database.
class _DemoStatements extends StatementsController {
  late final List<StatementRow> _rows = const StatementImporter()
      .parse(wordsFromText(sbiLayoutB))
      .rows;
  @override
  Future<void> load() async {}
  @override
  bool get hasLoaded => true;
  @override
  List<StatementAccount> get accounts => [
    StatementAccount(
      accountKey: 'SBI:7890',
      bank: 'SBI',
      accountMask: '7890',
      holderName: 'RAHUL VERMA',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 10, 1),
      files: 1,
      rows: _rows.length,
      verified: _rows.length,
    ),
  ];
  @override
  StatementAccount? get selected => accounts.first;
  @override
  List<StatementRow> get rows => _rows;
  @override
  StatementAnalysis? get analysis => const StatementImporter().analyse(_rows);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(_bytes('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      _bytes(
        '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    );
  await icons.load();
}

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(File(path).readAsBytesSync());

final GlobalKey _boundary = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 900));
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('docs/shots/render-$name.png').writeAsBytesSync(bytes!);
}

Future<void> _pump(WidgetTester tester, AppThemePreference theme) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(
    repository: DemoFinanceRepository(now: _now),
    permissions: const _Granted(),
    now: () => _now,
  );
  final themeModel = ThemeViewModel(initialPreference: theme);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: FinanceApp(
        appState: state,
        themeViewModel: themeModel,
        statements: _DemoStatements(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The app restores the saved preference on start; force the one rendered.
  await themeModel.setPreference(theme);
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, Widget page) async {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(MaterialPageRoute<void>(builder: (_) => page));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final theme in [AppThemePreference.light, AppThemePreference.dark]) {
    final t = theme.name;
    testWidgets('render $t', (tester) async {
      // flutter_test paints shadows unblurred by default; renders must look
      // like the phone. Restored before the test ends (a binding invariant).
      debugDisableShadows = false;
      try {
        await _render(tester, theme, t);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

Future<void> _render(
  WidgetTester tester,
  AppThemePreference theme,
  String t,
) async {
  await _pump(tester, theme);
  await _shot(tester, 'home-$t');
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
  await tester.pumpAndSettle();
  await _shot(tester, 'home-scroll-$t');
  for (final tab in ['Activity', 'Cards', 'Insights']) {
    await _tab(tester, tab);
    await _shot(tester, '${tab.toLowerCase()}-$t');
  }
  await _tab(tester, 'Home');
  await _push(tester, const SettingsScreen());
  await _shot(tester, 'settings-$t');
  Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
  await tester.pumpAndSettle();
  await _push(tester, const OnboardingScreen());
  await _shot(tester, 'onboarding-$t');
  Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
  await tester.pumpAndSettle();
  await _push(tester, const StatementsScreen());
  await _shot(tester, 'statements-$t');
  await _push(tester, SalaryCycleScreen(start: DateTime(2026, 9, 1)));
  await _shot(tester, 'cycle-$t');
}
