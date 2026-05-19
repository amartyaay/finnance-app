import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/sqlite_transaction_store.dart';
import 'repositories/transaction_repository.dart';
import 'services/csv_export_service.dart';
import 'services/permission_service.dart';
import 'services/sms_parser_service.dart';
import 'services/sms_reader_service.dart';
import 'viewmodels/home_view_model.dart';
import 'views/home_screen.dart';

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key, this.homeViewModel, this.autoInitialize = true});

  final HomeViewModel? homeViewModel;
  final bool autoInitialize;

  @override
  Widget build(BuildContext context) {
    final providedViewModel = homeViewModel;
    final child = MaterialApp(
      title: 'Finance SMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F7D4C),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F2),
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );

    if (providedViewModel != null) {
      if (autoInitialize) {
        unawaited(providedViewModel.initialize());
      }
      return ChangeNotifierProvider<HomeViewModel>.value(
        value: providedViewModel,
        child: child,
      );
    }

    return ChangeNotifierProvider<HomeViewModel>(
      create: (_) {
        final viewModel = _createHomeViewModel();
        if (autoInitialize) {
          unawaited(viewModel.initialize());
        }
        return viewModel;
      },
      child: child,
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
}
