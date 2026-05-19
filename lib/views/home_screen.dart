import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction_models.dart';
import '../services/permission_service.dart';
import '../utils/money_format.dart';
import '../viewmodels/home_view_model.dart';
import '../viewmodels/theme_view_model.dart';

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
          appBar: AppBar(
            title: const Text('Finance SMS'),
            actions: [
              const _ThemeMenuButton(),
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
                  _CreditCardSummarySection(viewModel: viewModel),
                  const SizedBox(height: 16),
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

class _ThemeMenuButton extends StatelessWidget {
  const _ThemeMenuButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeViewModel>(
      builder: (context, viewModel, _) {
        return PopupMenuButton<AppThemePreference>(
          tooltip: 'Theme',
          icon: const Icon(Icons.brightness_6_rounded),
          initialValue: viewModel.preference,
          onSelected: viewModel.setPreference,
          itemBuilder: (context) {
            return AppThemePreference.values
                .map((preference) {
                  return CheckedPopupMenuItem<AppThemePreference>(
                    value: preference,
                    checked: viewModel.preference == preference,
                    child: Text(viewModel.labelFor(preference)),
                  );
                })
                .toList(growable: false);
          },
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
    final colors = theme.colorScheme;
    final amountText = formatInrFromPaise(viewModel.monthlySpendPaise);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
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
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${viewModel.creditCardSummaries.length} cards detected from SMS',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onPrimaryContainer,
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            if (viewModel.lastScanResult != null) ...[
              const SizedBox(height: 12),
              Text(
                '${viewModel.lastScanResult!.parsedTransactions} parsed - '
                '${viewModel.lastScanResult!.insertedTransactions} new - '
                '${viewModel.lastScanResult!.totalSmsRead} SMS read',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
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
    final colors = theme.colorScheme;
    final isBlocked = viewModel.shouldOpenSettings;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
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
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
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

class _CreditCardSummarySection extends StatelessWidget {
  const _CreditCardSummarySection({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final summaries = viewModel.creditCardSummaries;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Detected credit cards',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text('${summaries.length}', style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 8),
        if (summaries.isEmpty)
          const _NoCardSummary()
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final summary in summaries) ...[
                  _CreditCardTile(summary: summary),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CreditCardTile extends StatelessWidget {
  const _CreditCardTile({required this.summary});

  final CreditCardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: 232,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.credit_card_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.issuer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      summary.maskedDigits,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('This month', style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            formatInrFromPaise(summary.monthlySpendPaise),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniMetric(
                icon: Icons.receipt_long_rounded,
                label: '${summary.transactionCount} SMS',
              ),
              _MiniMetric(
                icon: Icons.verified_rounded,
                label: '${(summary.confidence * 100).round()}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _NoCardSummary extends StatelessWidget {
  const _NoCardSummary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.credit_card_off_rounded, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No masked credit cards detected yet',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconForInstrument(transaction.instrument),
              color: colors.onPrimaryContainer,
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
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (transaction.cardIssuer != null) transaction.cardIssuer!,
                    transaction.sender,
                    if (transaction.cardLastDigits != null)
                      'xx${transaction.cardLastDigits}'
                    else if (transaction.accountOrCardHint != null)
                      'xx${transaction.accountOrCardHint}',
                  ].join(' - '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (transaction.categoryName != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      transaction.categoryName!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
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
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatScanTime(transaction.timestamp),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            viewModel.hasSmsPermission
                ? 'No transactions parsed yet'
                : 'Grant SMS access to start',
            style: theme.textTheme.titleMedium,
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
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
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
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: colors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

extension on FinanceTransaction {
  String get displayLabel {
    if (direction == TransactionDirection.transfer) {
      return 'Transfer or repayment';
    }

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
