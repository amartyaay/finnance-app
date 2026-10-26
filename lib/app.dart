import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'app/design_tokens.dart';
import 'app/theme.dart';
import 'app/widgets/kit.dart';
import 'state/app_state.dart';
import 'state/statements_controller.dart';
import 'viewmodels/theme_view_model.dart';
import 'services/daily_digest_channel.dart';
import 'views/budget_screen.dart';
import 'views/cards_screen.dart';
import 'views/tabs.dart';
import 'views/home_screen.dart';
import 'views/insights_screen.dart';
import 'views/onboarding_screen.dart';
import 'views/settings_screen.dart';
import 'views/sms_inbox_screen.dart';
import 'views/transactions_screen.dart';

/// Route name of the optional "All messages" review screen. Nothing in the
/// shell opens it on its own; any screen can call [openSmsInbox].
const String smsInboxRouteName = SmsInboxScreen.routeName;

/// Pushes the optional review screen. Its only entry points are an explicit
/// call (or, in the web build, `?tab=messages` for screenshots/deep links); it
/// never interrupts the app and always has a working Skip.
Future<void> openSmsInbox(BuildContext context) => SmsInboxScreen.open(context);

class FinanceApp extends StatefulWidget {
  const FinanceApp({
    super.key,
    this.appState,
    this.themeViewModel,
    this.autoInitialize = true,
    this.statements,
  });

  /// Injected by tests; the app builds its own.
  final StatementsController? statements;

  final AppState? appState;
  final ThemeViewModel? themeViewModel;
  final bool autoInitialize;

  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> {
  late final AppState _appState = widget.appState ?? AppState();
  late final ThemeViewModel _theme = widget.themeViewModel ?? ThemeViewModel();
  late final StatementsController _statements =
      widget.statements ??
      StatementsController(onLedgerChanged: () => _appState.refresh());

  @override
  void initState() {
    super.initState();
    if (widget.autoInitialize) {
      _theme.initialize();
      _appState.init();
      _statements.load();
      // The web build cannot read SMS, so it opens on generated demo data, and
      // it defaults to the light theme the design was built around (?theme=dark
      // opts out).
      if (kIsWeb) {
        _theme.setPreference(
          Uri.base.queryParameters['theme'] == 'dark'
              ? AppThemePreference.dark
              : AppThemePreference.light,
        );
        _appState.startDemo();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<ThemeViewModel>.value(value: _theme),
        ChangeNotifierProvider<StatementsController>.value(value: _statements),
      ],
      child: Consumer<ThemeViewModel>(
        builder: (context, theme, _) => MaterialApp(
          title: 'Hisaab',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(brightness: Brightness.dark),
          themeMode: theme.themeMode,
          // The aurora is painted once, under every route.
          builder: (context, child) => Stack(
            children: [
              const Positioned.fill(child: AuroraBackdrop()),
              ?child,
            ],
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// Five destinations; Settings is a pushed route from the header rather than a
/// sixth tab, since it is a rare visit.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _index = _initialTab(widget.initialIndex);

  /// A filter request for Activity, produced by another tab (e.g. the hero's
  /// transfers link). The serial makes a repeated request distinguishable.
  int _activitySerial = 0;
  ActivityRequest _activityRequest = const ActivityRequest();

  void _openActivity(ActivityRequest request) {
    setState(() {
      _activitySerial += 1;
      _activityRequest = request.withSerial(_activitySerial);
      _index = Tabs.activity;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _followLaunchTarget();
    // `?tab=messages` opens the optional review screen after the first frame;
    // it is a route push, never a launch modal, and Back/Skip dismiss it.
    if (kIsWeb && Uri.base.queryParameters['tab'] == 'messages') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(SmsInboxScreen.route());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _followLaunchTarget();
  }

  /// The 10 pm summary opens the app on Budget.
  Future<void> _followLaunchTarget() async {
    try {
      final target = await ChannelDigestScheduler.channel.invokeMethod<String>(
        'launchTarget',
      );
      if (target == 'budget' && mounted) setState(() => _index = Tabs.budget);
    } on Object {
      // No platform side (tests, other platforms): stay where we are.
    }
  }

  /// `?tab=2` lets screenshots and deep links land on a specific tab.
  static int _initialTab(int fallback) {
    if (!kIsWeb) return fallback;
    final parsed = int.tryParse(Uri.base.queryParameters['tab'] ?? '');
    if (parsed == null || parsed < 0 || parsed > 4) return fallback;
    return parsed;
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(PhosphorIconsRegular.house),
      selectedIcon: Icon(PhosphorIconsFill.house),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(PhosphorIconsRegular.listBullets),
      selectedIcon: Icon(PhosphorIconsBold.listBullets),
      label: 'Activity',
    ),
    NavigationDestination(
      icon: Icon(PhosphorIconsRegular.wallet),
      selectedIcon: Icon(PhosphorIconsFill.wallet),
      label: 'Budget',
    ),
    NavigationDestination(
      icon: Icon(PhosphorIconsRegular.creditCard),
      selectedIcon: Icon(PhosphorIconsFill.creditCard),
      label: 'Cards',
    ),
    NavigationDestination(
      icon: Icon(PhosphorIconsRegular.sparkle),
      selectedIcon: Icon(PhosphorIconsFill.sparkle),
      label: 'Insights',
    ),
  ];

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  /// Switches the visible tab. Shared with every screen that has an insight
  /// action, so "See cards" means the same thing from Home and from Insights.
  void _openTab(int index) {
    if (index < 0 || index >= _destinations.length) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.isLoading &&
        !state.isDemo &&
        !state.hasSmsPermission &&
        state.data.isEmpty) {
      return const OnboardingScreen();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              HomeScreen(
                onNavigate: _openTab,
                onOpenSettings: _openSettings,
                onOpenActivity: _openActivity,
              ),
              TransactionsScreen(request: _activityRequest),
              const BudgetScreen(),
              const CardsScreen(),
              InsightsScreen(
                onNavigate: _openTab,
                onOpenActivity: _openActivity,
              ),
            ],
          ),
        ],
      ),
      // A floating, frosted bar: it sits off the screen edge like a dock.
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(T.s3, 0, T.s3, T.s3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.r5),
            boxShadow: T.of(context).shadowCard,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(T.r5),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1626).withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(T.r5),
                  border: Border.all(color: T.glassEdge),
                ),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _openTab,
                  destinations: _destinations,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  height: 68,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
