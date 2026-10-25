import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/sms_inbox.dart';

final NumberFormat _countFormat = NumberFormat.decimalPattern('en_IN');

/// The funnel at the top of the inbox: what the scanner found, in four numbers,
/// plus the one thing the owner asked to be explicit — reviewing is optional.
class InboxFunnelHeader extends StatelessWidget {
  const InboxFunnelHeader({
    super.key,
    required this.stats,
    this.isDemo = false,
  });

  final InboxStats stats;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return AppCard(
      shadow: true,
      padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, T.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const IconBadge(icon: Icons.mark_email_unread_rounded),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDemo ? 'Demo inbox' : 'Your messages',
                      style: T.cardTitle.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Every stored SMS, newest first',
                      style: T.bodySmall.copyWith(color: p.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: T.s4),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - T.s2) / 2;
              return Wrap(
                spacing: T.s2,
                runSpacing: T.s3,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _FunnelStat(
                      value: stats.total,
                      label: 'Total messages',
                      color: p.ink,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _FunnelStat(
                      value: stats.transactions,
                      label: 'Transactions',
                      color: p.positive,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _FunnelStat(
                      value: stats.notCounted,
                      label: 'Not counted',
                      color: p.inkSecondary,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _FunnelStat(
                      value: stats.flagged,
                      label: 'Flagged',
                      color: p.danger,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: T.s3),
          Divider(height: 1, color: p.outlineVariant),
          const SizedBox(height: T.s3),
          Wrap(
            spacing: T.s2,
            runSpacing: T.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pill(
                '${_countFormat.format(stats.unreviewed)} unreviewed',
                tone: PillTone.caution,
                icon: Icons.help_outline_rounded,
                dense: true,
              ),
              Text(
                'Reviewing is optional — nothing changes unless you save.',
                style: T.bodySmall.copyWith(color: p.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FunnelStat extends StatelessWidget {
  const _FunnelStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _countFormat.format(value),
          style: T.moneyLarge(color).copyWith(fontSize: 21),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: T.bodySmall.copyWith(color: p.inkMuted),
          maxLines: 2,
        ),
      ],
    );
  }
}

/// The privacy promise, repeated at the end of the list where the eye lands.
class InboxPrivacyFooter extends StatelessWidget {
  const InboxPrivacyFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s2, T.s4, T.s2, T.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: p.inkMuted),
          const SizedBox(width: T.s2),
          Expanded(
            child: Text(
              'These are your messages, on this phone. Nothing is uploaded.',
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
