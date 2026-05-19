import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/sqlite_transaction_store.dart';
import 'repositories/transaction_repository.dart';
import 'services/csv_export_service.dart';
import 'services/permission_service.dart';
import 'services/sms_parser_service.dart';
import 'services/sms_reader_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/home_view_model.dart';
import 'viewmodels/theme_view_model.dart';
import 'views/home_screen.dart';

class FinanceApp extends StatefulWidget {
  const FinanceApp({
    super.key,
    this.homeViewModel,
    this.themeViewModel,
    this.autoInitialize = true,
  });

  final HomeViewModel? homeViewModel;
  final ThemeViewModel? themeViewModel;
  final bool autoInitialize;

  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> {
  @override
  void initState() {
    super.initState();
    if (widget.autoInitialize) {
      if (widget.themeViewModel != null) {
        unawaited(widget.themeViewModel!.initialize());
      }
      if (widget.homeViewModel != null) {
        unawaited(widget.homeViewModel!.initialize());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = [
      if (widget.themeViewModel != null)
        ChangeNotifierProvider<ThemeViewModel>.value(
          value: widget.themeViewModel!,
        )
      else
        ChangeNotifierProvider<ThemeViewModel>(
          create: (_) {
            final viewModel = _createThemeViewModel();
            if (widget.autoInitialize) {
              unawaited(viewModel.initialize());
            }
            return viewModel;
          },
        ),
      if (widget.homeViewModel != null)
        ChangeNotifierProvider<HomeViewModel>.value(
          value: widget.homeViewModel!,
        )
      else
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) {
            final viewModel = _createHomeViewModel();
            if (widget.autoInitialize) {
              unawaited(viewModel.initialize());
            }
            return viewModel;
          },
        ),
    ];

    return MultiProvider(
      providers: providers,
      child: Consumer<ThemeViewModel>(
        builder: (context, themeViewModel, _) {
          return MaterialApp(
            title: 'Finance SMS',
            debugShowCheckedModeBanner: false,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: themeViewModel.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  HomeViewModel _createHomeViewModel() {
    final transactionStore = SqliteTransactionStore();
    final repository = TransactionRepository(
      smsReaderService: const MethodChannelSmsReaderService(),
      smsParserService: DefaultSmsParserService(),
      transactionStore: transactionStore,
      csvExportService: const MethodChannelCsvExportService(),
    );
    return HomeViewModel(
      transactionRepository: repository,
      permissionService: const PermissionHandlerSmsPermissionService(),
    );
  }

  ThemeViewModel _createThemeViewModel() {
    return ThemeViewModel();
  }
}
