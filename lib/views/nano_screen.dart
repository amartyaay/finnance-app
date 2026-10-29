import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../domain/enums.dart';
import '../domain/transaction.dart';
import '../services/sms/gemini_nano.dart';
import '../state/app_state.dart';
import 'widgets/txn_common.dart';

/// Gemini Nano as a second opinion on the messages the parser was unsure
/// about. Started by the user, run while the app is on screen (AICore's rule),
/// and only ever a suggestion: nothing changes until the user taps.
class NanoScreen extends StatefulWidget {
  const NanoScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const NanoScreen()));

  @override
  State<NanoScreen> createState() => _NanoScreenState();
}

class _NanoScreenState extends State<NanoScreen> {
  static const _nano = GeminiNano();
  ({NanoStatus status, String? error})? _status;
  bool _busy = false;
  final _verdicts = <String, NanoVerdict>{};
  final _done = <String>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _nano.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _review(List<Txn> queue) async {
    setState(() => _busy = true);
    for (final txn in queue) {
      if (!mounted) return;
      if (_verdicts.containsKey(txn.key)) continue;
      final verdict = await _nano.classify(
        txn.sender ?? '',
        txn.rawBody ?? txn.title,
      );
      if (!mounted) return;
      setState(() => _verdicts[txn.key] = verdict);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.watch<AppState>();
    final queue = [
      for (final t in state.data.needsReview)
        if (!_done.contains(t.key)) t,
    ];
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('On-device AI'), titleSpacing: T.s5),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          T.s5,
          T.s2,
          T.s5,
          T.s8 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      PhosphorIconsFill.sparkle,
                      color: T.teal,
                      size: 20,
                    ),
                    const SizedBox(width: T.s3),
                    Expanded(
                      child: Text(
                        'Gemini Nano',
                        style: T.cardTitle.copyWith(color: p.ink),
                      ),
                    ),
                    if (status == null)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Pill(
                        status.status == NanoStatus.available
                            ? 'Ready'
                            : status.status == NanoStatus.unavailable
                            ? 'Not available'
                            : 'Download',
                        tone: status.status == NanoStatus.available
                            ? PillTone.positive
                            : status.status == NanoStatus.unavailable
                            ? PillTone.neutral
                            : PillTone.info,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: T.s2),
                Text(
                  status?.status.label ?? 'Checking this phone…',
                  style: T.body.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: T.s2),
                Text(
                  "Google's small on-device model, run by Android's AICore. It "
                  'reads a message on this phone and says whether money moved. '
                  'It only runs while Hisaab is open, so it checks messages you '
                  'choose to review; your SMS never leave the phone.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
                if (status?.error != null &&
                    status!.status == NanoStatus.unavailable) ...[
                  const SizedBox(height: T.s2),
                  Text(
                    'AICore said: ${status.error}',
                    style: T.bodySmall.copyWith(
                      color: p.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (status?.status == NanoStatus.downloadable) ...[
                  const SizedBox(height: T.s3),
                  FilledButton(
                    onPressed: () async {
                      setState(
                        () => _status = (
                          status: NanoStatus.downloading,
                          error: null,
                        ),
                      );
                      await _nano.download();
                      await _refresh();
                    },
                    child: const Text('Download the model (by Android)'),
                  ),
                ],
              ],
            ),
          ),
          if (status?.status == NanoStatus.available) ...[
            const SizedBox(height: T.s5),
            SectionHeader(
              title: 'Messages to confirm',
              subtitle: queue.isEmpty
                  ? 'Nothing waiting for review'
                  : 'The parser was unsure about these. Ask Gemini Nano.',
              action: queue.isEmpty || _busy ? null : 'Ask',
              onAction: () => _review(queue),
              padding: const EdgeInsets.only(bottom: T.s2),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            for (final txn in queue)
              _VerdictRow(
                txn: txn,
                verdict: _verdicts[txn.key],
                onNotTransaction: () async {
                  await state.notATransaction(txn);
                  setState(() => _done.add(txn.key));
                },
                onKeep: () async {
                  final kind = txn.categoryKind;
                  await state.setCategory(
                    txn,
                    txn.categoryName ?? categoryKindLabel(kind),
                    kind,
                  );
                  setState(() => _done.add(txn.key));
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({
    required this.txn,
    required this.verdict,
    required this.onNotTransaction,
    required this.onKeep,
  });

  final Txn txn;
  final NanoVerdict? verdict;
  final VoidCallback onNotTransaction;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final parser = switch (txn.kind) {
      TxnKind.spend => 'a spend',
      TxnKind.income => 'money in',
      TxnKind.transfer => 'a transfer',
      TxnKind.cash => 'cash',
    };
    final (label, tone) = switch (verdict) {
      null => ('Not asked yet', PillTone.neutral),
      NanoVerdict.spent => ('Nano: money spent', PillTone.info),
      NanoVerdict.received => ('Nano: money in', PillTone.info),
      NanoVerdict.nothing => ('Nano: not a transaction', PillTone.caution),
      NanoVerdict.unsure => ('Nano: unsure', PillTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s3),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName(txn.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.cardTitle.copyWith(color: p.ink),
                  ),
                ),
                Text(
                  money(txn.amount),
                  style: T.money.copyWith(color: p.ink, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: T.s1),
            Text(
              txn.rawBody ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: T.s2),
            Wrap(
              spacing: T.s2,
              runSpacing: T.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Pill('Parser: $parser', dense: true),
                Pill(label, tone: tone, dense: true),
              ],
            ),
            if (verdict != null) ...[
              const SizedBox(height: T.s2),
              Row(
                children: [
                  TextButton(
                    onPressed: onNotTransaction,
                    child: const Text('Not a transaction'),
                  ),
                  const Spacer(),
                  TextButton(onPressed: onKeep, child: const Text('Keep it')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
