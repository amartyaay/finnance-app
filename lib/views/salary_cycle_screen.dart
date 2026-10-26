import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../domain/money.dart';
import '../domain/statement.dart';
import '../engine/salary_cycles.dart';
import '../state/statements_controller.dart';
import 'widgets/salary_cycle_card.dart';
import 'widgets/txn_common.dart';

/// One salary-to-salary cycle: where the money went, and every row behind it.
/// Tapping a credit lets the user mark (or unmark) it as salary.
class SalaryCycleScreen extends StatelessWidget {
  const SalaryCycleScreen({super.key, required this.start});

  /// The cycle is looked up by its start each build, so a salary override
  /// (which can move cycle boundaries) redraws from fresh data.
  final DateTime start;

  static Future<void> open(BuildContext context, SalaryCycle cycle) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SalaryCycleScreen(start: cycle.start),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<StatementsController>();
    final p = T.of(context);
    final cycles = controller.analysis?.cycles ?? const <SalaryCycle>[];
    final cycle =
        cycles.where((c) => c.start == start).firstOrNull ??
        cycles.where((c) => !c.start.isAfter(start)).firstOrNull;
    if (cycle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cycle')),
        body: const EmptyState(
          icon: Icons.event_busy_rounded,
          title: 'This cycle changed',
          body:
              'Marking a salary moved the cycle boundaries. Go back to see the new cycles.',
        ),
      );
    }

    final categories = cycle.spendByCategory
        .where((e) => e.value != 0)
        .toList();
    final spent = cycle.spentPaise;
    final segments = cycleSegments(context, cycle);
    final rows = [...cycle.rows]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(titleSpacing: T.s5, title: Text(cycleRange(cycle))),
      body: ListView(
        // Same gutter as the tabs, and clear of the gesture bar.
        padding: EdgeInsets.fromLTRB(
          T.s5,
          T.s2,
          T.s5,
          T.s8 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          SalaryCycleCard(cycle: cycle),
          const SizedBox(height: T.s4),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('In and out', style: T.cardTitle.copyWith(color: p.ink)),
                const SizedBox(height: T.s2),
                _Line('Salary', cycle.salaryPaise, color: p.positive),
                if (cycle.otherInPaise > 0)
                  _Line('Interest and other credits', cycle.otherInPaise),
                for (final s in segments) _Line(s.label, s.paise, dot: s.color),
                const Divider(height: T.s5),
                _Line(
                  cycle.leftPaise >= 0
                      ? 'Saved (incl. invested)'
                      : 'Spent more than came in',
                  cycle.leftPaise.abs(),
                  bold: true,
                  color: cycle.leftPaise >= 0 ? p.ink : p.danger,
                ),
                const SizedBox(height: T.s2),
                Text(
                  'Card bills are what you paid your card company this cycle; the '
                  'purchases themselves are on the Cards tab. Money moved between '
                  'your own accounts is not counted.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              ],
            ),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: T.s5),
            const SectionHeader(title: 'Spent by category'),
            AppCard(
              child: Column(
                children: [
                  for (final e in categories)
                    _CategoryLine(
                      name: e.key,
                      paise: e.value,
                      share: spent <= 0 ? 0 : e.value / spent,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: T.s5),
          SectionHeader(
            title: 'All transactions',
            subtitle: 'Tap a credit to mark it as your salary, or not.',
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final row in rows)
                  _RowTile(row: row, isSalary: cycle.salaryRows.contains(row)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.paise, {
    this.color,
    this.dot,
    this.bold = false,
  });

  final String label;
  final int paise;
  final Color? color;
  final Color? dot;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: T.s2),
          ],
          Expanded(
            child: Text(
              label,
              style: (bold ? T.label : T.body).copyWith(color: p.inkSecondary),
            ),
          ),
          const SizedBox(width: T.s2),
          Text(
            money(Paise(paise)),
            style: T.money.copyWith(
              color: color ?? p.ink,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({
    required this.name,
    required this.paise,
    required this.share,
  });

  final String name;
  final int paise;
  final double share;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s1 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: T.body.copyWith(color: p.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: T.s2),
              Text(
                paise < 0 ? '−${money(Paise(-paise))}' : money(Paise(paise)),
                style: T.money.copyWith(color: p.ink),
              ),
            ],
          ),
          const SizedBox(height: T.s1),
          ClipRRect(
            borderRadius: BorderRadius.circular(T.r1),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: p.surfaceSunken,
              color: p.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.isSalary});

  final StatementRow row;
  final bool isSalary;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final title = row.counterparty ?? row.description;
    final kindLabel = isSalary ? 'Salary' : row.kind.label;
    final amount = row.isDebit
        ? '−${money(Paise(row.debitPaise))}'
        : '+${money(Paise(row.creditPaise))}';
    return InkWell(
      onTap: () => _showRow(context, row, isSalary),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s4, vertical: T.s2),
          child: Row(
            children: [
              IconBadge(
                icon: isSalary
                    ? Icons.payments_rounded
                    : categoryIcon(row.categoryKind),
                color: isSalary
                    ? p.positive
                    : categoryColor(context, row.categoryKind),
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: T.body.copyWith(color: p.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${DateFormat('d MMM').format(row.date)} · $kindLabel'
                      '${row.balanceVerified ? '' : ' · balance not checked'}',
                      style: T.bodySmall.copyWith(color: p.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: T.s2),
              Text(
                amount,
                style: T.money.copyWith(
                  color: row.isDebit ? p.ink : p.positive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showRow(BuildContext context, StatementRow row, bool isSalary) {
  final controller = context.read<StatementsController>();
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final p = T.of(context);
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.isDebit
                    ? money(Paise(row.debitPaise))
                    : '+${money(Paise(row.creditPaise))}',
                style: T
                    .moneyLarge(row.isDebit ? p.ink : p.positive)
                    .copyWith(fontSize: 28),
              ),
              const SizedBox(height: T.s1),
              Text(
                '${DateFormat('EEE, d MMM yyyy').format(row.date)} · ${isSalary ? 'Salary' : row.kind.label}',
                style: T.bodySmall.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: T.s3),
              SoftSection(
                child: Text(
                  row.description,
                  style: T.bodySmall.copyWith(color: p.inkSecondary),
                ),
              ),
              if (row.balancePaise != null) ...[
                const SizedBox(height: T.s2),
                Text(
                  'Balance after: ${money(Paise(row.balancePaise!))} '
                  '${row.balanceVerified ? '· checked against the previous row' : '· did not add up with the previous row'}',
                  style: T.bodySmall.copyWith(
                    color: row.balanceVerified ? p.inkMuted : p.caution,
                  ),
                ),
              ],
              if (!row.isDebit) ...[
                const SizedBox(height: T.s4),
                Text(
                  'Is this your salary?',
                  style: T.label.copyWith(color: p.ink),
                ),
                const SizedBox(height: T.s2),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          controller.setSalary(row, false);
                          Navigator.pop(context);
                        },
                        child: const Text('Not salary'),
                      ),
                    ),
                    const SizedBox(width: T.s3),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          controller.setSalary(row, true);
                          Navigator.pop(context);
                        },
                        child: const Text('My salary'),
                      ),
                    ),
                  ],
                ),
                if (row.isSalaryOverride != null)
                  TextButton(
                    onPressed: () {
                      controller.setSalary(row, null);
                      Navigator.pop(context);
                    },
                    child: const Text('Let the app decide again'),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
