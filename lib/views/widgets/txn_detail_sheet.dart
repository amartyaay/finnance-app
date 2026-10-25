import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/transaction.dart';
import '../../state/app_state.dart';
import 'txn_common.dart';

/// Opens the full record for one message: every parsed field, why the parser was
/// confident, and the category picker that writes the fix back to the store.
Future<void> showTransactionDetail(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _TransactionDetailSheet(initial: txn),
  );
}

class _TransactionDetailSheet extends StatelessWidget {
  const _TransactionDetailSheet({required this.initial});

  final Txn initial;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final txn = _current(state.data.transactions, initial);
    final amountColor = txn.kind == TxnKind.income
        ? T.primary
        : txn.kind == TxnKind.spend
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final amountText = txn.kind == TxnKind.income
        ? '+${inr(txn.amount)}'
        : inr(txn.amount);
    final cardLabel = <String>[
      if (txn.issuer != null && txn.issuer!.isNotEmpty) txn.issuer!,
      if (txn.last4 != null && txn.last4!.isNotEmpty) '•••• ${txn.last4}',
    ].join(' · ');
    final raw = txn.rawBody?.trim();
    final categories = state.data.categories;
    final options = categories.isEmpty
        ? [
            for (final kind in SpendCategoryKind.values)
              categoryKindLabel(kind),
          ]
        : categories;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: categoryColor(
                      txn.categoryKind,
                    ).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(T.r2),
                  ),
                  child: Icon(
                    categoryIcon(txn.categoryKind),
                    size: 20,
                    color: categoryColor(txn.categoryKind),
                  ),
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Text(
                    txn.title,
                    style: T.title.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: T.s4),
            Text(amountText, style: T.moneyLarge(amountColor)),
            const SizedBox(height: T.s1),
            Text(
              '${shortDateWithYear(txn.occurredAt)} · ${clockTime(txn.occurredAt)}',
              style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (txn.needsReview) ...[
              const SizedBox(height: T.s2),
              const Pill('Needs review', tone: PillTone.caution, dense: true),
            ],
            const SizedBox(height: T.s5),
            Text(
              'Category',
              style: T.label.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: T.s2),
            Wrap(
              spacing: T.s2,
              runSpacing: T.s2,
              children: [
                for (final name in options)
                  ChoiceChip(
                    label: Text(name),
                    showCheckmark: false,
                    selected:
                        txn.categoryName?.trim().toLowerCase() ==
                        name.trim().toLowerCase(),
                    onSelected: (_) async {
                      final kind = categoryKindForName(
                        name,
                        state.data.transactions,
                      );
                      await state.setCategory(txn, name, kind);
                    },
                  ),
              ],
            ),
            const SizedBox(height: T.s5),
            const Divider(height: 1),
            const SizedBox(height: T.s2),
            _DetailRow(label: 'Instrument', value: txn.instrument.label),
            if (cardLabel.isNotEmpty)
              _DetailRow(label: 'Card', value: cardLabel),
            if (txn.referenceId?.trim().isNotEmpty == true)
              _DetailRow(
                label: 'Reference',
                value: txn.referenceId!.trim(),
                monospace: true,
              ),
            const SizedBox(height: T.s4),
            Text(
              'Parsed with ${(txn.confidence * 100).round()}% confidence',
              style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: T.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(T.r1),
              child: LinearProgressIndicator(
                value: txn.confidence.clamp(0.0, 1.0).toDouble(),
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(
                  txn.confidence >= 0.8
                      ? T.positive
                      : txn.confidence >= 0.5
                      ? T.caution
                      : T.danger,
                ),
              ),
            ),
            if (raw != null && raw.isNotEmpty) ...[
              const SizedBox(height: T.s4),
              Text(
                'Message',
                style: T.label.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: T.s2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(T.s3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(T.r2),
                ),
                child: Text(
                  raw,
                  style: T.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (txn.isDuplicateOfKey != null) ...[
              const SizedBox(height: T.s4),
              Container(
                padding: const EdgeInsets.all(T.s3),
                decoration: BoxDecoration(
                  color: T.infoSoft,
                  borderRadius: BorderRadius.circular(T.r2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.call_merge_rounded,
                      size: 18,
                      color: T.info,
                    ),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text(
                        'This is a duplicate. It was merged into the original '
                        'alert so your spend counts the payment once.',
                        style: T.bodySmall.copyWith(color: T.info),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The sheet outlives a category change, so always re-read the row from state
  /// instead of showing the snapshot it was opened with.
  Txn _current(List<Txn> transactions, Txn fallback) {
    for (final txn in transactions) {
      if (txn.key == fallback.key) return txn;
    }
    return fallback;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s1 + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: T.body.copyWith(
                color: scheme.onSurface,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
