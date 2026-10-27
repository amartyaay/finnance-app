import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/transaction.dart';
import '../../engine/card_bill_breakdown.dart';
import '../../app/money_format.dart';
import '../../state/app_state.dart';
import 'txn_common.dart';

/// Opens the full record for one message: every parsed field, why the parser was
/// confident, and the category picker that writes the fix back to the store.
Future<void> showTransactionDetail(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        SafeArea(top: false, child: _TransactionDetailSheet(initial: txn)),
  );
}

class _TransactionDetailSheet extends StatelessWidget {
  const _TransactionDetailSheet({required this.initial});

  final Txn initial;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = T.of(context);
    final txn = _current(state.data.transactions, initial);
    final amountColor = txn.kind == TxnKind.income
        ? p.primary
        : txn.kind == TxnKind.spend
        ? p.ink
        : p.inkMuted;
    final prefix = txn.kind == TxnKind.income
        ? '+'
        : txn.kind == TxnKind.spend
        ? '−'
        : null;
    final cardLabel = <String>[
      if (txn.issuer != null && txn.issuer!.isNotEmpty) txn.issuer!,
      if (txn.last4 != null && txn.last4!.isNotEmpty) '•••• ${txn.last4}',
    ].join(' · ');
    final raw = txn.rawBody?.trim();
    final categories = state.data.categories;
    final options = categories.isEmpty
        ? [for (final kind in SpendCategoryKind.values) categoryKindLabel(kind)]
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
                IconBadge(
                  icon: categoryIcon(txn.categoryKind),
                  color: categoryColor(context, txn.categoryKind),
                  size: 42,
                  iconSize: 21,
                  radius: T.r3,
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Text(
                    displayName(txn.title),
                    style: T.title.copyWith(color: p.ink, fontSize: 19),
                  ),
                ),
              ],
            ),
            const SizedBox(height: T.s4),
            MoneyText(
              txn.amount,
              prefix: prefix,
              style: T.moneyLarge(amountColor).copyWith(fontSize: 30),
              color: amountColor,
            ),
            const SizedBox(height: T.s1),
            Text(
              '${shortDateWithYear(txn.occurredAt)} · ${clockTime(txn.occurredAt)}',
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
            if (txn.needsReview) ...[
              const SizedBox(height: T.s2),
              const Pill('Needs review', tone: PillTone.caution, dense: true),
            ],
            const SizedBox(height: T.s5),
            Text('Category', style: T.label.copyWith(color: p.inkSecondary)),
            if (txn.sourceType == TxnSourceType.statement &&
                (txn.merchant?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 2),
              Text(
                'Applies to this and later payments to ${displayName(txn.merchant!)}.',
                style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: T.s2),
            // Each chip's 48 dp tap box already spaces the rows.
            Wrap(
              spacing: T.s2,
              runSpacing: 0,
              children: [
                for (final name in options)
                  _CategoryChoice(
                    name: name,
                    selected:
                        txn.categoryName?.trim().toLowerCase() ==
                        name.trim().toLowerCase(),
                    onTap: () async {
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
            Divider(height: 1, color: p.outlineVariant),
            const SizedBox(height: T.s2),
            if (txn.sourceType == TxnSourceType.statement)
              const _DetailRow(label: 'Source', value: 'Bank statement')
            else
              _DetailRow(label: 'Instrument', value: txn.instrument.label),
            if (cardLabel.isNotEmpty)
              _DetailRow(
                label: txn.sourceType == TxnSourceType.statement
                    ? 'Account'
                    : 'Card',
                value: cardLabel,
              ),
            if (txn.referenceId?.trim().isNotEmpty == true)
              _DetailRow(
                label: 'Reference',
                value: txn.referenceId!.trim(),
                monospace: true,
              ),
            if (CardBillBreakdown.of(
                  txn,
                  state.data.transactions,
                  notices: state.data.billNotices,
                )
                case final breakdown?) ...[
              const SizedBox(height: T.s4),
              _BillBreakdown(breakdown: breakdown, payment: txn),
            ],
            const SizedBox(height: T.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Parsed with ${(txn.confidence * 100).round()}% confidence',
                    style: T.bodySmall.copyWith(color: p.inkMuted),
                  ),
                ),
                Icon(
                  txn.confidence >= 0.8
                      ? Icons.verified_rounded
                      : txn.confidence >= 0.5
                      ? Icons.help_rounded
                      : Icons.warning_rounded,
                  size: 16,
                  color: txn.confidence >= 0.8
                      ? p.positive
                      : txn.confidence >= 0.5
                      ? p.caution
                      : p.danger,
                ),
              ],
            ),
            const SizedBox(height: T.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(T.r1),
              child: LinearProgressIndicator(
                value: txn.confidence.clamp(0.0, 1.0).toDouble(),
                minHeight: 6,
                backgroundColor: p.surfaceSunken,
                valueColor: AlwaysStoppedAnimation<Color>(
                  txn.confidence >= 0.8
                      ? p.positive
                      : txn.confidence >= 0.5
                      ? p.caution
                      : p.danger,
                ),
              ),
            ),
            if (raw != null && raw.isNotEmpty) ...[
              const SizedBox(height: T.s4),
              Text(
                txn.sourceType == TxnSourceType.statement
                    ? 'Statement narration'
                    : 'Message',
                style: T.label.copyWith(color: p.inkSecondary),
              ),
              const SizedBox(height: T.s2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(T.s3),
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(T.r2),
                ),
                child: Text(
                  raw,
                  style: T.bodySmall.copyWith(
                    color: p.inkSecondary,
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
                  color: p.infoSoft,
                  borderRadius: BorderRadius.circular(T.r2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.call_merge_rounded, size: 18, color: p.info),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text(
                        'This is a duplicate. It was merged into the original '
                        'alert so your spend counts the payment once.',
                        style: T.bodySmall.copyWith(color: p.info),
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

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        // 48 dp tall to tap, but only as wide as the chip: an aligned
        // Container expands to the Wrap's full width, one chip per row.
        child: SizedBox(
          height: 48,
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: T.fast,
              height: 36,
              // Centre the label in the pill: without it the text sat at
              // the top of the 34 dp box.
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: T.s4),
              decoration: BoxDecoration(
                color: selected ? p.ink : p.surfaceMuted,
                borderRadius: BorderRadius.circular(T.r5),
                border: Border.all(color: selected ? p.ink : p.outlineVariant),
              ),
              child: Text(
                name,
                maxLines: 1,
                style: T.bodySmall.copyWith(
                  color: selected ? p.bg : p.inkSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final p = T.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s1 + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: T.bodySmall.copyWith(color: p.inkMuted)),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: T.body.copyWith(
                color: p.ink,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "What this paid for": the card's own purchases behind one bill payment,
/// by category. The bank statement shows a single debit; the card's SMS fill
/// in the detail.
class _BillBreakdown extends StatelessWidget {
  const _BillBreakdown({required this.breakdown, required this.payment});

  final CardBillBreakdown breakdown;
  final Txn payment;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final card = breakdown.cardKey.replaceAll('|', ' ••');
    final rows = breakdown.byCategory;
    // The last day counted (the window's end is exclusive of the next day).
    final lastDay = breakdown.to.subtract(const Duration(minutes: 1));
    final firstDay = breakdown.from;
    final window = breakdown.byStatement
        ? 'on the card statement of ${shortDate(breakdown.statementDate!)} '
              '(${shortDate(firstDay)} – ${shortDate(lastDay)})'
        : '${shortDate(firstDay)} – ${shortDate(lastDay)}, since the previous '
              'payment (no statement SMS for this card)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(T.s4),
      decoration: T.glass(radius: T.r3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What this paid for', style: T.cardTitle.copyWith(color: p.ink)),
          const SizedBox(height: 2),
          Text(
            '${rows.isEmpty
                ? 'No purchases'
                : breakdown.count == 1
                ? '1 purchase'
                : '${breakdown.count} purchases'} '
            'on $card in your SMS, $window.',
            style: T.bodySmall.copyWith(color: p.inkMuted),
          ),
          for (final r in rows) ...[
            const SizedBox(height: T.s3),
            Row(
              children: [
                Icon(
                  categoryIcon(r.kind),
                  size: 18,
                  color: categoryColor(context, r.kind),
                ),
                const SizedBox(width: T.s2),
                Expanded(
                  child: Text(
                    '${r.name} · ${r.count}',
                    style: T.body.copyWith(color: p.ink),
                  ),
                ),
                Text(
                  money(Paise(r.paise)),
                  style: T.money.copyWith(color: p.ink, fontSize: 14),
                ),
              ],
            ),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: T.s3),
            Text(
              [
                if (breakdown.statementTotalPaise != null)
                  'Statement total ${money(Paise(breakdown.statementTotalPaise!))}.',
                'Purchases found ${money(Paise(breakdown.totalPaise))}; this '
                    'payment ${money(payment.amount)}.',
                if (breakdown.totalPaise != payment.amountPaise)
                  'A bill also carries earlier balance, EMIs, fees and refunds, '
                      'and purchases with no SMS are not listed.',
              ].join(' '),
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
