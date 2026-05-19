import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction_models.dart';
import '../services/permission_service.dart';
import '../utils/money_format.dart';
import '../viewmodels/home_view_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<HomeViewModel>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, viewModel, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF6F7F2),
          appBar: AppBar(
            title: const Text('Finance SMS'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: viewModel.isScanning
                    ? null
                    : () => viewModel.scanInbox(),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => viewModel.openSettings(),
                icon: const Icon(Icons.settings_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: viewModel.scanInbox,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _HeaderPanel(viewModel: viewModel),
                  const SizedBox(height: 12),
                  if (viewModel.permissionState != SmsPermissionState.granted)
                    _PermissionPanel(viewModel: viewModel),
                  if (viewModel.permissionState != SmsPermissionState.granted)
                    const SizedBox(height: 12),
                  if (viewModel.uncategorizedTransactions.isNotEmpty) ...[
                    _PendingCategoryPanel(viewModel: viewModel),
                    const SizedBox(height: 12),
                  ],
                  _RecentHeader(viewModel: viewModel),
                  const SizedBox(height: 8),
                  if (viewModel.recentTransactions.isEmpty)
                    _EmptyState(viewModel: viewModel)
                  else
                    ...viewModel.recentTransactions.map(
                      (transaction) =>
                          _TransactionItem(transaction: transaction),
                    ),
                  if (viewModel.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: viewModel.errorMessage!),
                  ],
                  if (viewModel.exportMessage != null) ...[
                    const SizedBox(height: 12),
                    _InfoBanner(message: viewModel.exportMessage!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountText = formatInrFromPaise(viewModel.monthlySpendPaise);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7DA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This month', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              amountText,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF164B2F),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: viewModel.isScanning ? null : viewModel.scanInbox,
                  icon: viewModel.isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sms_rounded),
                  label: Text(viewModel.isScanning ? 'Scanning' : 'Scan inbox'),
                ),
                OutlinedButton.icon(
                  onPressed: viewModel.isExporting
                      ? null
                      : () => viewModel.exportCsv(),
                  icon: viewModel.isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_rounded),
                  label: Text(
                    viewModel.isExporting ? 'Exporting' : 'Export CSV',
                  ),
                ),
                Text(
                  'Last scan: ${formatScanTime(viewModel.lastScanAt)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            if (viewModel.lastScanResult != null) ...[
              const SizedBox(height: 12),
              Text(
                '${viewModel.lastScanResult!.parsedTransactions} parsed - '
                '${viewModel.lastScanResult!.insertedTransactions} new - '
                '${viewModel.lastScanResult!.totalSmsRead} SMS read',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBlocked = viewModel.shouldOpenSettings;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF4EE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7C7B2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded),
                const SizedBox(width: 8),
                Text('SMS access required', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Reads transaction alerts on this phone only, watches for new SMS, and shows classification notifications. Raw SMS is not uploaded.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: isBlocked
                      ? viewModel.openSettings
                      : viewModel.requestPermissionAndScan,
                  icon: const Icon(Icons.sms_rounded),
                  label: Text(isBlocked ? 'Open settings' : 'Allow SMS'),
                ),
                if (viewModel.isUnsupported)
                  const Text('SMS reading is only available on Android.'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCategoryPanel extends StatefulWidget {
  const _PendingCategoryPanel({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<_PendingCategoryPanel> createState() => _PendingCategoryPanelState();
}

class _PendingCategoryPanelState extends State<_PendingCategoryPanel> {
  final TextEditingController _categoryController = TextEditingController();

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final transaction = viewModel.uncategorizedTransactions.first;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7DA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Classify latest expense',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${viewModel.uncategorizedTransactions.length} pending',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${formatInrFromPaise(transaction.amountPaise)} - '
              '${transaction.merchantOrPayee ?? transaction.displayLabel}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in viewModel.categories)
                  ActionChip(
                    avatar: const Icon(Icons.label_rounded, size: 18),
                    label: Text(category.name),
                    onPressed: () => viewModel.classifyTransaction(
                      transaction: transaction,
                      category: category,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Add custom category',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addAndUse(transaction),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _addAndUse(transaction),
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAndUse(FinanceTransaction transaction) async {
    final name = _categoryController.text;
    await widget.viewModel.addCategoryAndClassify(
      transaction: transaction,
      categoryName: name,
    );
    _categoryController.clear();
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Recent transactions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          '${viewModel.recentTransactions.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }
}

class _TransactionItem extends StatelessWidget {
  const _TransactionItem({required this.transaction});

  final FinanceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7E8E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3E7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconForInstrument(transaction.instrument),
              color: const Color(0xFF245338),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.merchantOrPayee?.isNotEmpty == true
                      ? transaction.merchantOrPayee!
                      : transaction.displayLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    transaction.sender,
                    if (transaction.accountOrCardHint != null)
                      'xx${transaction.accountOrCardHint}',
                  ].join(' - '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (transaction.categoryName != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4EA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      transaction.categoryName!,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatInrFromPaise(transaction.amountPaise),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                formatScanTime(transaction.timestamp),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForInstrument(TransactionInstrument instrument) {
    switch (instrument) {
      case TransactionInstrument.upi:
        return Icons.qr_code_2_rounded;
      case TransactionInstrument.debitCard:
        return Icons.credit_card_rounded;
      case TransactionInstrument.creditCard:
        return Icons.receipt_long_rounded;
      case TransactionInstrument.account:
        return Icons.account_balance_rounded;
      case TransactionInstrument.wallet:
        return Icons.account_balance_wallet_rounded;
      case TransactionInstrument.unknown:
        return Icons.payments_rounded;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7E8E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            viewModel.hasSmsPermission
                ? 'No transactions parsed yet'
                : 'Grant SMS access to start',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            viewModel.hasSmsPermission
                ? 'Tap Scan inbox after granting permission. Only expense alerts are counted.'
                : 'The app reads transaction alerts from SMS and keeps the data on this device.',
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF1B9B4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFF9F3A31)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBD7F6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF235A8D)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

extension on FinanceTransaction {
  String get displayLabel {
    switch (instrument) {
      case TransactionInstrument.upi:
        return 'UPI payment';
      case TransactionInstrument.debitCard:
        return 'Debit card spend';
      case TransactionInstrument.creditCard:
        return 'Card spend';
      case TransactionInstrument.account:
        return 'Account debit';
      case TransactionInstrument.wallet:
        return 'Wallet spend';
      case TransactionInstrument.unknown:
        return 'Expense';
    }
  }
}
