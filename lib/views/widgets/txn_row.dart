import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/money_format.dart';
import '../../app/widgets/kit.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/transaction.dart';
import 'txn_common.dart';

/// Where a [TxnRow]'s text starts (padding + icon + gap): dividers between
/// rows start here so they line up with the text, not the icon.
const double txnRowTextInset = T.s4 + 40 + T.s3;

/// One line in the Activity list. Dense on purpose: the list is for scanning,
/// the bottom sheet is for reading.
class TxnRow extends StatelessWidget {
  const TxnRow({super.key, required this.txn, required this.onTap});

  final Txn txn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final accent = categoryColor(context, txn.categoryKind);
    final amountColor = switch (txn.kind) {
      TxnKind.income => p.primary,
      TxnKind.spend => p.ink,
      TxnKind.transfer => p.inkMuted,
      TxnKind.cash => p.inkMuted,
    };
    final prefix = txn.kind == TxnKind.income
        ? '+'
        : txn.kind == TxnKind.spend
        ? '−'
        : null;
    final categoryLabel = txn.categoryName?.trim().isNotEmpty == true
        ? txn.categoryName!.trim()
        : categoryKindLabel(txn.categoryKind);
    // An inflow is described by what it actually is — a refund, a cashback, a
    // P2P credit or a card-bill credit is money in, but calling it "Income"
    // would contradict a hero that correctly says no income arrived.
    final moneyIn = txn.moneyInKind;
    final descriptor = moneyIn.isInflow ? moneyIn.label : categoryLabel;
    // "Credit-card bill payment · Card bill payment" repeats itself; keep the
    // descriptor only when the merchant line does not already say it.
    final showDescriptor = !txn.title.toLowerCase().contains(
      descriptor.toLowerCase(),
    );
    final details = <String>[
      if (showDescriptor) descriptor,
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
      '${prefix == '+'
          ? 'plus '
          : prefix == '−'
          ? 'minus '
          : ''}${money(txn.amount)}',
      if (merged) 'Merged duplicate',
      if (!merged && txn.needsReview) 'Needs review',
    ].join('. ');

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: T.s4,
                vertical: T.s2 + 2,
              ),
              child: Row(
                children: [
                  IconBadge(
                    icon: categoryIcon(txn.categoryKind),
                    color: accent,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: T.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName(txn.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.cardTitle.copyWith(color: p.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MoneyText(
                        txn.amount,
                        prefix: prefix,
                        style: T.money.copyWith(fontSize: 14),
                        color: amountColor,
                      ),
                      if (pill != null) ...[const SizedBox(height: T.s1), pill],
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

/// Day separator above a grouped day card: the day name on the left, what left
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
    final p = T.of(context);
    final hasOutflow = outflow.isPositive;
    final total = hasOutflow
        ? money(outflow)
        : inflow.isPositive
        ? '+${money(inflow)}'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, T.s5, 0, T.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dayHeading(day, viewNow(context)),
              style: T.cardTitle.copyWith(
                color: p.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (total != null)
            Text(
              total,
              maxLines: 1,
              softWrap: false,
              style: T.money.copyWith(
                color: hasOutflow ? p.inkSecondary : p.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
