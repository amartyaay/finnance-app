import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/design_tokens.dart';
import '../../app/money_format.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/salary_cycles.dart';

/// "1 Sep – 30 Sep" for a cycle (its end is exclusive: the next payday).
String cycleRange(SalaryCycle cycle) {
  final f = DateFormat('d MMM');
  final last = cycle.end.subtract(const Duration(days: 1));
  return '${f.format(cycle.start)} – ${f.format(last)}';
}

/// The pieces of a cycle's outflow, in display order, with their colours.
List<({String label, int paise, Color color})> cycleSegments(
  BuildContext context,
  SalaryCycle cycle,
) {
  final p = T.of(context);
  return [
    (label: 'Spent', paise: cycle.spentPaise, color: p.accent),
    (label: 'Card bills', paise: cycle.cardBillsPaise, color: p.info),
    (label: 'Cash', paise: cycle.cashPaise, color: p.caution),
    (label: 'EMI / loans', paise: cycle.loanPaise, color: p.danger),
    (label: 'Invested', paise: cycle.investedPaise, color: p.primary),
  ].where((s) => s.paise > 0).toList();
}

class SalaryCycleCard extends StatelessWidget {
  const SalaryCycleCard({super.key, required this.cycle, this.onTap});

  final SalaryCycle cycle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final income = cycle.salaryPaise + cycle.otherInPaise;
    final left = cycle.leftPaise;
    final segments = cycleSegments(context, cycle);
    final total = segments.fold<int>(0, (s, x) => s + x.paise) + (left > 0 ? left - cycle.investedPaise : 0);
    final status = cycle.salaryRows.isEmpty
        ? 'Before first salary'
        : cycle.isPartial
        ? 'In progress · ${cycle.days} days'
        : '${cycle.days} days';
    final categories = cycle.spendByCategory.where((e) => e.value > 0).take(3).toList();

    return AppCard(
      onTap: onTap,
      child: Semantics(
        label: 'Cycle ${cycleRange(cycle)}. Salary ${moneySpoken(Paise(cycle.salaryPaise))}. '
            '${left >= 0 ? 'Left' : 'Overspent'} ${moneySpoken(Paise(left.abs()))}.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cycleRange(cycle),
                    style: T.cardTitle.copyWith(color: p.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: T.s2),
                Flexible(
                  child: Pill(
                    status,
                    dense: true,
                    tone: cycle.isPartial ? PillTone.info : PillTone.neutral,
                  ),
                ),
              ],
            ),
            const SizedBox(height: T.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        income == 0
                            ? 'Money out'
                            : left < 0
                            ? 'Spent more than came in'
                            : cycle.isPartial
                            ? 'Left so far'
                            : 'Saved this cycle',
                        style: T.label.copyWith(color: p.inkSecondary),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          income == 0
                              ? money(Paise(cycle.outPaise))
                              : money(Paise(left.abs())),
                          style: T.moneyLarge(
                            income > 0 && left < 0 ? p.danger : p.ink,
                          ).copyWith(fontSize: 26),
                        ),
                      ),
                    ],
                  ),
                ),
                if (cycle.salaryPaise > 0)
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Salary', style: T.label.copyWith(color: p.inkSecondary)),
                        Text(
                          money(Paise(cycle.salaryPaise)),
                          style: T.money.copyWith(color: p.positive),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: T.s3),
              ClipRRect(
                borderRadius: BorderRadius.circular(T.r1),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      for (final s in segments)
                        Expanded(
                          flex: (s.paise * 1000 ~/ total).clamp(1, 1000),
                          child: Container(color: s.color),
                        ),
                      if (left - cycle.investedPaise > 0)
                        Expanded(
                          flex: ((left - cycle.investedPaise) * 1000 ~/ total).clamp(1, 1000),
                          child: Container(color: p.surfaceSunken),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: T.s2),
              Wrap(
                spacing: T.s4,
                runSpacing: T.s1,
                children: [
                  for (final s in segments)
                    _Legend(color: s.color, label: s.label, paise: s.paise),
                ],
              ),
            ],
            if (categories.isNotEmpty) ...[
              const SizedBox(height: T.s3),
              Text(
                'Most went to ${categories.map((e) => e.key).join(', ')}',
                style: T.bodySmall.copyWith(color: p.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.paise});

  final Color color;
  final String label;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: T.s1),
        Text(
          '$label ${moneyCompact(Paise(paise))}',
          style: T.bodySmall.copyWith(color: p.inkSecondary),
        ),
      ],
    );
  }
}
