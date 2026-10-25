import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/category_catalog.dart';
import '../../domain/enums.dart';
import '../../domain/inbox_store.dart';
import '../../domain/merchant_signature.dart';
import '../../domain/money.dart';
import '../../domain/sms_inbox.dart';
import '../../domain/transaction.dart';
import '../../state/app_state.dart';
import 'inbox_common.dart';

/// What the sheet did, so the screen can reload and say so in a SnackBar.
class InboxSheetOutcome {
  const InboxSheetOutcome(this.message);

  final String message;
}

Future<InboxSheetOutcome?> showInboxMessageSheet(
  BuildContext context, {
  required SmsMessageRow row,
  required InboxStore store,
  required InboxRowStatus status,
  Txn? parsed,
  Txn? stored,
}) {
  return showModalBottomSheet<InboxSheetOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _InboxMessageSheet(
      row: row,
      store: store,
      status: status,
      parsed: parsed,
      stored: stored,
    ),
  );
}

class _InboxMessageSheet extends StatefulWidget {
  const _InboxMessageSheet({
    required this.row,
    required this.store,
    required this.status,
    this.parsed,
    this.stored,
  });

  final SmsMessageRow row;
  final InboxStore store;
  final InboxRowStatus status;
  final Txn? parsed;
  final Txn? stored;

  @override
  State<_InboxMessageSheet> createState() => _InboxMessageSheetState();
}

class _InboxMessageSheetState extends State<_InboxMessageSheet> {
  late final Txn? _txn = widget.stored ?? widget.parsed;
  late final String? _signature = MerchantSignature.of(
    _txn?.merchant,
    senderEntity: senderEntity(widget.row.sender),
  );
  late final String _merchantLabel = merchantScopeLabel(
    _txn,
    widget.row.sender,
  );
  late final bool _hasTransaction = widget.status == InboxRowStatus.transaction;
  late final TextEditingController _amount = TextEditingController(
    text: _txn == null ? '' : (_txn.amountPaise / 100).toStringAsFixed(
      _txn.amountPaise % 100 == 0 ? 0 : 2,
    ),
  );
  late final TextEditingController _merchant = TextEditingController(
    text: _txn?.merchant ?? '',
  );

  String? _category;
  late bool _everyPayment;
  bool _busy = false;
  bool _showCreateForm = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _everyPayment = _signature != null;
    final category = _txn?.categoryName?.trim();
    final owned =
        _txn != null &&
        (_txn.categorySource == CategorySource.user ||
            _txn.categorySource == CategorySource.learned);
    if (owned && category != null && category.isNotEmpty) {
      _category = category;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  void _close() {
    if (_busy) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_busy) return;
    final category = _category;
    if (category == null) {
      setState(() => _error = 'Pick a category first.');
      return;
    }
    final kind = inboxCategoryKind(category);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String message;
      if (_everyPayment && _signature != null) {
        final count = await widget.store.applyCategoryToSignature(
          signature: _signature,
          categoryName: category,
          kind: kind,
        );
        message = count == 1
            ? 'Saved. 1 earlier payment from $_merchantLabel updated.'
            : count > 1
            ? 'Saved. $count earlier payments from $_merchantLabel updated.'
            : 'Saved. New payments from $_merchantLabel will use this category.';
      } else if (_txn != null) {
        await widget.store.assignCategoryOnce(
          txnKey: _txn.key,
          categoryName: category,
          kind: kind,
        );
        message = 'Saved for this payment only.';
      } else {
        setState(() {
          _busy = false;
          _error = 'There is no parsed payment to update. Use “This is a '
              'transaction” below.';
        });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(InboxSheetOutcome(message));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save that. Try again.';
      });
    }
  }

  Future<void> _notATransaction() async {
    if (_busy) return;
    final every = _everyPayment && _signature != null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final removed = await widget.store.markNotTransaction(
        signature: _signature,
        messageId: widget.row.id,
        txnKey: _txn?.key ?? messageTxnKey(widget.row),
        everyFromMerchant: every,
      );
      final String message;
      if (removed > 0) {
        final label = removed == 1 ? 'payment' : 'payments';
        message = every
            ? 'Removed $removed $label from $_merchantLabel out of your '
                  'totals. Future alerts from there stay out.'
            : 'Removed this $label from your totals.';
      } else {
        message = 'Marked as not a transaction.';
      }
      if (!mounted) return;
      Navigator.of(context).pop(InboxSheetOutcome(message));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not exclude that. Try again.';
      });
    }
  }

  Future<void> _createTransaction() async {
    if (_busy) return;
    final amount = parseAmountToPaise(_amount.text.trim());
    if (amount == null || amount.isZero) {
      setState(() => _error = 'Enter the amount you paid.');
      return;
    }
    final merchant = _merchant.text.trim();
    if (merchant.isEmpty) {
      setState(() => _error = 'Add the merchant or person you paid.');
      return;
    }
    final category = _category;
    if (category == null) {
      setState(() => _error = 'Pick a category first.');
      return;
    }
    final signature = MerchantSignature.of(
      merchant,
      senderEntity: senderEntity(widget.row.sender),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.createTransactionFromMessage(
        message: widget.row,
        amountPaise: amount.value,
        merchant: merchant,
        categoryName: category,
        kind: inboxCategoryKind(category),
        rememberMerchant: _everyPayment && signature != null,
        signature: signature,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        InboxSheetOutcome(
          'Added ${inr(amount)} at $merchant to your ledger.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not add that payment. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.watch<AppState>();
    final options = state.data.categories.isEmpty
        ? categoryCatalog.keys.toList(growable: false)
        : state.data.categories;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
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
                          'Message',
                          style: T.title.copyWith(color: p.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          messageTimestamp(widget.row.receivedAt),
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  _SemanticIconButton(
                    label: 'Close message',
                    icon: Icons.close_rounded,
                    onTap: _close,
                  ),
                ],
              ),
              const SizedBox(height: T.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friendlySender(widget.row.sender),
                          style: T.cardTitle.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.row.sender,
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  Pill(
                    widget.status.label,
                    tone: inboxStatusTone(widget.status),
                    icon: inboxStatusIcon(widget.status),
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: T.s4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(T.s3),
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(T.r2),
                  border: Border.all(color: p.outlineVariant),
                ),
                child: SelectableText(
                  widget.row.body,
                  style: T.bodySmall.copyWith(
                    color: p.inkSecondary,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
              SectionHeader(
                title: 'Parsed result',
                subtitle: _txn == null
                    ? 'Nothing here reads as a payment.'
                    : null,
                padding: const EdgeInsets.only(top: T.s5, bottom: T.s2),
              ),
              if (_txn == null)
                Text(
                  'If money did move, mark it as a transaction below and the '
                  'app will count it.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                )
              else
                _ParsedResult(txn: _txn),
              SectionHeader(
                title: 'Category',
                subtitle: _hasTransaction
                    ? 'Pick one, then choose how far it should reach.'
                    : 'Only needed if this message is really a payment.',
                padding: const EdgeInsets.only(top: T.s5, bottom: T.s2),
              ),
              Wrap(
                spacing: T.s2,
                runSpacing: T.s2,
                children: [
                  for (final name in options)
                    ChoiceChip(
                      label: Text(name),
                      showCheckmark: false,
                      selected: _category == name,
                      onSelected: (_) => setState(() {
                        _category = name;
                        _error = null;
                      }),
                    ),
                ],
              ),
              SectionHeader(
                title: 'Apply to',
                padding: const EdgeInsets.only(top: T.s5, bottom: T.s2),
              ),
              _ScopeOption(
                title: 'Just this payment',
                subtitle: 'Only this message changes. Nothing is remembered.',
                selected: !_everyPayment,
                onTap: () => setState(() => _everyPayment = false),
              ),
              const SizedBox(height: T.s2),
              _ScopeOption(
                title: _signature == null
                    ? 'Every payment from this sender'
                    : 'Every payment from $_merchantLabel',
                subtitle: _signature == null
                    ? 'This sender has no name to group payments by.'
                    : 'Also updates every earlier payment from this merchant '
                          'and remembers the choice for new ones.',
                selected: _everyPayment,
                enabled: _signature != null,
                onTap: () => setState(() => _everyPayment = true),
              ),
              if (_error != null) ...[
                const SizedBox(height: T.s3),
                Text(
                  _error!,
                  style: T.bodySmall.copyWith(
                    color: p.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: T.s5),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
              const SizedBox(height: T.s2),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : _notATransaction,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('Not a transaction'),
                ),
              ),
              if (!_hasTransaction) ...[
                const SizedBox(height: T.s2),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _showCreateForm = !_showCreateForm,
                          ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('This is a transaction'),
                  ),
                ),
                if (_showCreateForm) ...[
                  const SizedBox(height: T.s3),
                  AppCard(
                    color: p.surfaceMuted,
                    border: false,
                    padding: const EdgeInsets.all(T.s3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add the payment',
                          style: T.cardTitle.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: T.s2),
                        TextField(
                          controller: _amount,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '₹ ',
                          ),
                        ),
                        const SizedBox(height: T.s2),
                        TextField(
                          controller: _merchant,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Merchant or payee',
                          ),
                        ),
                        const SizedBox(height: T.s3),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: _busy ? null : _createTransaction,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text('Add payment'),
                          ),
                        ),
                        const SizedBox(height: T.s1),
                        Text(
                          'Saved with the category and scope above.',
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: T.s3),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _close,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParsedResult extends StatelessWidget {
  const _ParsedResult({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultRow(
          label: 'Amount',
          child: MoneyText(
            txn.amount,
            style: T.money.copyWith(color: p.ink),
            prefix: txn.kind == TxnKind.income ? '+' : null,
          ),
        ),
        _ResultRow(
          label: 'Kind',
          child: Text(
            txnKindLabel(txn.kind),
            style: T.body.copyWith(color: p.ink),
            textAlign: TextAlign.end,
          ),
        ),
        _ResultRow(
          label: 'Instrument',
          child: Text(
            txn.instrument.label,
            style: T.body.copyWith(color: p.ink),
            textAlign: TextAlign.end,
          ),
        ),
        _ResultRow(
          label: 'Merchant',
          child: Text(
            txn.merchant?.trim().isNotEmpty == true
                ? txn.merchant!
                : 'Not named',
            style: T.body.copyWith(color: p.ink),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.child});

  final String label;
  final Widget child;

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
            child: Text(
              label,
              style: T.bodySmall.copyWith(color: p.inkMuted),
              maxLines: 2,
            ),
          ),
          const SizedBox(width: T.s2),
          Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final active = enabled;
    final borderColor = selected && active ? p.primary : p.outlineVariant;
    final fill = selected && active ? p.primarySoft : p.surfaceMuted;
    return Semantics(
      button: true,
      selected: selected,
      enabled: active,
      label: '$title. $subtitle',
      onTap: active ? onTap : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: active ? onTap : null,
          borderRadius: BorderRadius.circular(T.r2),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: T.s3,
              vertical: T.s2,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(T.r2),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected && active
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: !active
                        ? p.inkMuted.withValues(alpha: 0.5)
                        : selected
                        ? p.primary
                        : p.inkMuted,
                  ),
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: T.cardTitle.copyWith(
                          color: active ? p.ink : p.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: T.bodySmall.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SemanticIconButton extends StatelessWidget {
  const _SemanticIconButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: p.inkSecondary),
          ),
        ),
      ),
    );
  }
}
