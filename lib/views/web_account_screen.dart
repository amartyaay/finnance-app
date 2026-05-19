import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/theme_view_model.dart';

class WebAccountScreen extends StatelessWidget {
  const WebAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance SMS Web'),
        actions: const [_ThemeMenuButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WebHeader(colors: colors, theme: theme),
                    const SizedBox(height: 14),
                    const _MetricGrid(),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (!isWide) {
                          return const Column(
                            children: [
                              _AnalysisPanel(),
                              SizedBox(height: 14),
                              _CardsPanel(),
                              SizedBox(height: 14),
                              _WebTransactionsPanel(),
                            ],
                          );
                        }

                        return const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: _AnalysisPanel()),
                            SizedBox(width: 14),
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  _CardsPanel(),
                                  SizedBox(height: 14),
                                  _WebTransactionsPanel(),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
                .map(
                  (preference) => CheckedPopupMenuItem<AppThemePreference>(
                    value: preference,
                    checked: viewModel.preference == preference,
                    child: Text(viewModel.labelFor(preference)),
                  ),
                )
                .toList(growable: false);
          },
        );
      },
    );
  }
}

class _WebHeader extends StatelessWidget {
  const _WebHeader({required this.colors, required this.theme});

  final ColorScheme colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          return Flex(
            direction: isWide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: isWide
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: isWide ? 1 : 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account overview', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Rs. 42,850',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'May spending across UPI, cards, bills, and wallets',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isWide) const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _HeaderPill(icon: Icons.cloud_off_rounded, label: 'UI only'),
                  _HeaderPill(icon: Icons.sms_failed_rounded, label: 'No SMS on web'),
                  _HeaderPill(icon: Icons.lock_rounded, label: 'Google account'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid();

  static const _metrics = [
    _MetricData(Icons.restaurant_rounded, 'Food', 'Rs. 12,420', '+8%'),
    _MetricData(Icons.directions_car_rounded, 'Travel', 'Rs. 8,100', '-3%'),
    _MetricData(Icons.school_rounded, 'Education', 'Rs. 6,800', 'Flat'),
    _MetricData(Icons.receipt_long_rounded, 'Bills', 'Rs. 9,530', '+2%'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.4 : 2.6,
          children: [
            for (final metric in _metrics) _MetricCard(metric: metric),
          ],
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData(this.icon, this.label, this.value, this.change);

  final IconData icon;
  final String label;
  final String value;
  final String change;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _MetricData metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, color: colors.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(metric.label, style: theme.textTheme.labelLarge),
                Text(
                  metric.value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Text(metric.change, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel();

  static const _bars = [
    _BarData('Food', 0.78),
    _BarData('Travel', 0.52),
    _BarData('Bills', 0.61),
    _BarData('Lifestyle', 0.34),
    _BarData('Education', 0.44),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _Panel(
      title: 'Analysis',
      icon: Icons.query_stats_rounded,
      child: Column(
        children: [
          for (final bar in _bars) ...[
            _SpendBar(label: bar.label, value: bar.value),
            const SizedBox(height: 12),
          ],
          Divider(color: colors.outlineVariant),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.insights_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Food and bills are driving most of this month\'s visible spend.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarData {
  const _BarData(this.label, this.value);

  final String label;
  final double value;
}

class _SpendBar extends StatelessWidget {
  const _SpendBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
            Text('${(value * 100).round()}%', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _CardsPanel extends StatelessWidget {
  const _CardsPanel();

  static const _cards = [
    _CardData('ICICI Bank', 'xx4321', 'Rs. 18,450'),
    _CardData('SBI Card', 'xx0987', 'Rs. 9,980'),
    _CardData('Kotak', 'xx7788', 'Rs. 4,120'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Credit cards',
      icon: Icons.credit_card_rounded,
      child: Column(
        children: [
          for (final card in _cards) ...[
            _WebCardRow(card: card),
            if (card != _cards.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CardData {
  const _CardData(this.issuer, this.digits, this.spend);

  final String issuer;
  final String digits;
  final String spend;
}

class _WebCardRow extends StatelessWidget {
  const _WebCardRow({required this.card});

  final _CardData card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.credit_card_rounded, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.issuer, style: theme.textTheme.titleSmall),
                Text(card.digits, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            card.spend,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebTransactionsPanel extends StatelessWidget {
  const _WebTransactionsPanel();

  static const _transactions = [
    _TransactionData('Zomato', 'Food', 'Rs. 620'),
    _TransactionData('Uber', 'Travel', 'Rs. 410'),
    _TransactionData('Amazon', 'Lifestyle', 'Rs. 2,499'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Recent activity',
      icon: Icons.receipt_long_rounded,
      child: Column(
        children: [
          for (final transaction in _transactions) ...[
            _WebTransactionRow(transaction: transaction),
            if (transaction != _transactions.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TransactionData {
  const _TransactionData(this.merchant, this.category, this.amount);

  final String merchant;
  final String category;
  final String amount;
}

class _WebTransactionRow extends StatelessWidget {
  const _WebTransactionRow({required this.transaction});

  final _TransactionData transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.payments_rounded,
            color: colors.onTertiaryContainer,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(transaction.merchant, style: theme.textTheme.titleSmall),
              Text(transaction.category, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Text(transaction.amount, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(icon, color: colors.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
