import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/category_catalog.dart';
import '../../domain/enums.dart';
import '../../domain/hashing.dart';
import '../../domain/sms_inbox.dart';
import '../../domain/transaction.dart';
import '../../engine/merchant_learning.dart';
import '../../services/sms/sender_registry.dart';
import 'txn_common.dart';

const SenderRegistry _senderRegistry = SenderRegistry();
const MerchantLearning _learning = MerchantLearning();

/// The bank/shop name behind a DLT header, with the raw id as fallback.
String friendlySender(String rawSender) {
  final resolved = _senderRegistry.resolve(rawSender);
  final entity = resolved.entity;
  if (entity != null && entity.trim().isNotEmpty) return entity;
  return rawSender.trim().isEmpty ? 'Unknown sender' : rawSender.trim();
}

/// The resolved entity only (used for the merchant-signature fallback).
String? senderEntity(String rawSender) =>
    _learning.senderEntityFor(rawSender);

/// Deterministic key of the ledger row derived from a message. The extractor
/// uses exactly this value, so a message and its payment can be paired without
/// a join column.
String messageTxnKey(SmsMessageRow row) =>
    'sms:${smsContentId(sender: row.sender, receivedAtMs: row.receivedAtMs, body: row.body)}';

String messageAge(DateTime at, DateTime now) {
  final difference = now.difference(at);
  if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) {
    final hours = difference.inHours;
    return hours <= 0 ? 'Just now' : '${hours}h ago';
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  if (at.year == now.year) return shortDate(at);
  return shortDateWithYear(at);
}

String messageTimestamp(DateTime at) =>
    '${shortDateWithYear(at)} · ${clockTime(at)}';

String txnKindLabel(TxnKind kind) => switch (kind) {
  TxnKind.spend => 'Spend',
  TxnKind.cash => 'Cash withdrawal',
  TxnKind.income => 'Income',
  TxnKind.transfer => 'Transfer',
};

PillTone inboxStatusTone(InboxRowStatus status) => switch (status) {
  InboxRowStatus.transaction => PillTone.positive,
  InboxRowStatus.notCounted => PillTone.neutral,
  InboxRowStatus.flagged => PillTone.danger,
  InboxRowStatus.review => PillTone.caution,
  InboxRowStatus.possiblyMissed => PillTone.info,
};

IconData inboxStatusIcon(InboxRowStatus status) => switch (status) {
  InboxRowStatus.transaction => Icons.check_circle_rounded,
  InboxRowStatus.notCounted => Icons.remove_circle_outline_rounded,
  InboxRowStatus.flagged => Icons.gpp_bad_rounded,
  InboxRowStatus.review => Icons.help_outline_rounded,
  InboxRowStatus.possiblyMissed => Icons.manage_search_rounded,
};

Color inboxStatusColor(BuildContext context, InboxRowStatus status) {
  final p = T.of(context);
  return switch (status) {
    InboxRowStatus.transaction => p.positive,
    InboxRowStatus.notCounted => p.inkMuted,
    InboxRowStatus.flagged => p.danger,
    InboxRowStatus.review => p.caution,
    InboxRowStatus.possiblyMissed => p.info,
  };
}

/// Category name -> the engine's coarse kind, using the one bundled catalogue.
SpendCategoryKind inboxCategoryKind(String name) => categoryKindFor(name);

/// What the scope radio should call the merchant the rule is keyed on.
String merchantScopeLabel(Txn? txn, String rawSender) {
  final merchant = txn?.merchant?.trim();
  if (merchant != null && merchant.isNotEmpty) return merchant;
  return friendlySender(rawSender);
}

/// True when the message's parsed payment shape is already covered by a
/// remembered "not a transaction" rule.
bool isExcludedShape(Txn? txn, Set<String> excludedShapes) =>
    txn != null &&
    excludedShapes.isNotEmpty &&
    excludedShapes.contains(_learning.exclusionFor(txn));
