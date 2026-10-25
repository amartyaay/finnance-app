import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/sms_inbox.dart';
import '../../domain/transaction.dart';
import 'inbox_common.dart';

/// One row: friendly sender, relative date, a status chip, the parsed amount
/// (for payments) and the message body clamped to two lines.
class InboxMessageTile extends StatelessWidget {
  const InboxMessageTile({
    super.key,
    required this.row,
    required this.parsed,
    required this.stored,
    required this.status,
    required this.now,
    required this.onTap,
  });

  final SmsMessageRow row;

  /// What the extractor reads from the text right now.
  final Txn? parsed;

  /// The stored ledger row for this message, when one exists (it carries the
  /// category after a save and is authoritative for amount/merchant).
  final Txn? stored;

  final InboxRowStatus status;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final txn = stored ?? parsed;
    final category = txn?.categoryName?.trim();
    final categoryIsOwned =
        txn != null &&
        (txn.categorySource == CategorySource.user ||
            txn.categorySource == CategorySource.learned);
    final showCategory =
        status == InboxRowStatus.transaction &&
        categoryIsOwned &&
        category != null &&
        category.isNotEmpty;
    final tone = inboxStatusTone(status);

    return Semantics(
      label:
          '${friendlySender(row.sender)}, ${messageAge(row.receivedAt, now)}, '
          '${status.label}',
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(T.s4, T.s3 + 2, T.s4, T.s3 + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friendlySender(row.sender),
                        style: T.cardTitle.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        messageAge(row.receivedAt, now),
                        style: T.bodySmall.copyWith(color: p.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: T.s2),
                Pill(
                  status.label,
                  tone: tone,
                  icon: inboxStatusIcon(status),
                  dense: true,
                ),
              ],
            ),
            if (status == InboxRowStatus.transaction && txn != null) ...[
              const SizedBox(height: T.s3),
              Wrap(
                spacing: T.s2,
                runSpacing: T.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MoneyText(
                    Paise(txn.amountPaise),
                    style: T.money.copyWith(fontSize: 16, color: p.ink),
                    prefix: txn.kind == TxnKind.income ? '+' : null,
                  ),
                  Text(
                    txn.title,
                    style: T.bodySmall.copyWith(
                      color: p.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showCategory)
                    Pill(category, tone: PillTone.brand, dense: true),
                ],
              ),
            ],
            const SizedBox(height: T.s2),
            _ExpandableBody(text: row.body),
          ],
        ),
      ),
    );
  }
}

/// The body, two lines until the owner asks for the rest. The "Show more"
/// control is a real 48 dp button, separate from the row tap that opens the
/// full message.
class _ExpandableBody extends StatefulWidget {
  const _ExpandableBody({required this.text});

  final String text;

  @override
  State<_ExpandableBody> createState() => _ExpandableBodyState();
}

class _ExpandableBodyState extends State<_ExpandableBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final style = T.body.copyWith(
      color: p.inkSecondary,
      fontSize: 13.5,
      height: 1.42,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  tapTargetSize: MaterialTapTargetSize.padded,
                  foregroundColor: p.primary,
                  textStyle: T.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.primary,
                  ),
                ),
                child: Text(_expanded ? 'Show less' : 'Show more'),
              ),
          ],
        );
      },
    );
  }
}
