import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/design_tokens.dart';
import '../../app/money_format.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/card_metrics.dart';
import '../../state/app_state.dart';

/// The settings list for cards. Limits and cycle days are the two facts only the
/// user can supply, so they live behind an explicit edit action per card.
class CardLimitsCard extends StatelessWidget {
  const CardLimitsCard({super.key, required this.cards});

  final List<CardMetrics> cards;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, T.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Card limits & dates',
            style: T.cardTitle.copyWith(color: p.ink, fontSize: 16),
          ),
          const SizedBox(height: T.s1),
          Text(
            'Utilisation is only accurate when we know the limit.',
            style: T.bodySmall.copyWith(color: p.inkMuted),
          ),
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.outlineVariant),
            _CardLimitRow(metrics: cards[i]),
          ],
        ],
      ),
    );
  }
}

class _CardLimitRow extends StatelessWidget {
  const _CardLimitRow({required this.metrics});

  final CardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final card = metrics.card;
    final limit = card.creditLimitPaise;
    final facts = <String>[
      limit == null ? 'Limit not set' : money(Paise(limit)),
      card.statementDay == null
          ? 'statement day not set'
          : 'statement ${card.statementDay}',
      card.dueDay == null ? 'due day not set' : 'due ${card.dueDay}',
    ];
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: T.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${card.masked} · ${facts.join(' · ')}',
                  maxLines: 2,
                  style: T.bodySmall.copyWith(
                    color: p.inkMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Edit ${card.displayName} limit and dates',
          onPressed: () => showCardEditSheet(context, card),
          icon: const Icon(Icons.edit_rounded),
          color: p.inkSecondary,
        ),
      ],
    );
  }
}

Future<void> showCardEditSheet(BuildContext context, CardAccount card) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _CardEditSheet(card: card),
  );
}

class _CardEditSheet extends StatefulWidget {
  const _CardEditSheet({required this.card});

  final CardAccount card;

  @override
  State<_CardEditSheet> createState() => _CardEditSheetState();
}

class _CardEditSheetState extends State<_CardEditSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.card.label ?? '',
  );
  late final TextEditingController _limit = TextEditingController(
    text: _initialLimit(),
  );
  late final TextEditingController _statement = TextEditingController(
    text: widget.card.statementDay?.toString() ?? '',
  );
  late final TextEditingController _due = TextEditingController(
    text: widget.card.dueDay?.toString() ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _limit.dispose();
    _statement.dispose();
    _due.dispose();
    super.dispose();
  }

  String _initialLimit() {
    final paise = widget.card.creditLimitPaise;
    if (paise == null) return '';
    return (paise ~/ 100).toString();
  }

  int? _day(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null) return null;
    return value.clamp(1, 28).toInt();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final rupees = int.tryParse(_limit.text.trim());
    final label = _label.text.trim();
    setState(() => _saving = true);
    await state.saveCard(
      widget.card.copyWith(
        // copyWith cannot clear a field, so an empty box keeps the stored value.
        label: label.isEmpty ? null : label,
        creditLimitPaise: rupees == null ? null : rupees * 100,
        statementDay: _day(_statement),
        dueDay: _day(_due),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Card limits & dates',
              style: T.title.copyWith(color: p.ink),
            ),
            const SizedBox(height: T.s1),
            Text(
              '${widget.card.issuer} · ${widget.card.masked}',
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: T.s4),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Travel card',
              ),
            ),
            const SizedBox(height: T.s3),
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Credit limit',
                prefixText: '₹ ',
                hintText: '450000',
                helperText: 'Whole rupees.',
              ),
            ),
            const SizedBox(height: T.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _statement,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    maxLength: 2,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Statement day',
                      helperText: '1–28',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: TextField(
                    controller: _due,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 2,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Due day',
                      helperText: '1–28',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: T.s3),
            Text(
              'We only use these to work out utilisation and due dates.',
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: T.s4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
