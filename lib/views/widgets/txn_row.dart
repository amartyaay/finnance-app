import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/transaction.dart';
import 'txn_common.dart';

/// One line in the Activity list. Dense on purpose: the list is for scanning,
/// the bottom sheet is for reading.
class TxnRow extends StatelessWidget {
  const TxnRow({super.key, required this.txn, required this.onTap});

  final Txn txn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = categoryColor(txn.categoryKind);
    final amountColor = switch (txn.kind) {
      TxnKind.income => T.primary,
      TxnKind.spend => scheme.onSurface,
      TxnKind.transfer => scheme.onSurfaceVariant,
      TxnKind.cash => scheme.onSurfaceVariant,
    };
    final amountText = txn.kind == TxnKind.income
        ? '+${inr(txn.amount)}'
        : inr(txn.amount);
    final categoryLabel = txn.categoryName?.trim().isNotEmpty == true
        ? txn.categoryName!.trim()
        : categoryKindLabel(txn.categoryKind);
    final details = <String>[
      categoryLabel,
      txn.instrument.label,
      if (txn.last4 != null && txn.last4!.isNotEmpty) '•••• ${txn.last4}',
    ].join(' · ');

    final bool merged = txn.isDuplicateOfKey != null;
    final Widget? pill = merged
        ? const Pill('Merged', dense: true)
        : txn.needsReview
        ? const Pill('Review', tone: PillTone.caution, dense: true)
        : null;

    final semantics = [
      txn.title,
      details,
      amountText,
      if (merged) 'Merged duplicate',
      if (!merged && txn.needsReview) 'Needs review',
    ].join('. ');

    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.r2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: T.s1,
                vertical: T.s2,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(T.r2),
                    ),
                    child: Icon(
                      categoryIcon(txn.categoryKind),
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: T.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          txn.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.cardTitle.copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        amountText,
                        style: T.money.copyWith(color: amountColor),
                      ),
                      if (pill != null) ...[
                        const SizedBox(height: T.s1),
                        pill,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Day separator inside the Activity list: the day name on the left, what left
/// the account that day on the right.
class TxnDayHeader extends StatelessWidget {
  const TxnDayHeader({
    super.key,
    required this.day,
    required this.outflow,
    required this.inflow,
  });

  final DateTime day;
  final Paise outflow;
  final Paise inflow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasOutflow = outflow.isPositive;
    final total = hasOutflow
        ? inr(outflow)
        : inflow.isPositive
        ? '+${inr(inflow)}'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s1, T.s4, T.s1, T.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dayHeading(day, DateTime.now()),
              style: T.label.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (total != null)
            Text(
              total,
              style: T.bodySmall.copyWith(
                color: hasOutflow ? scheme.onSurfaceVariant : T.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
