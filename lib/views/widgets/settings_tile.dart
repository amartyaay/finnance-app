import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';

/// A grouped settings card with hairline dividers between rows.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, indent: T.s4));
      rows.add(children[i]);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(T.r3),
        child: Column(children: rows),
      ),
    );
  }
}

/// One settings row: icon, title, explanation, optional trailing control.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = danger
        ? T.danger
        : enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: T.s4,
        vertical: T.s3,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: danger ? T.dangerSoft : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(T.r2),
            ),
            child: Icon(
              icon,
              size: 19,
              color: danger
                  ? T.danger
                  : enabled
                  ? scheme.onSurfaceVariant
                  : scheme.outline,
            ),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(color: foreground),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: T.bodySmall.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: T.s2),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: enabled ? onTap : null, child: row),
      ),
    );
  }
}

/// The one place that explains the parser's three checks, reachable from
/// Settings > About.
Future<void> showParsingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How parsing works', style: T.title),
            const SizedBox(height: T.s1),
            Text(
              'Three checks run on every message before a rupee reaches your '
              'totals.',
              style: T.body.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: T.s5),
            const _ParsingPoint(
              number: '1',
              title: 'Sender id trust',
              body:
                  'The sender header is matched against known bank and wallet '
                  'IDs. A plausible name alone never turns a message into a '
                  'transaction.',
            ),
            const _ParsingPoint(
              number: '2',
              title: 'Amount scoring',
              body:
                  'When a message carries several numbers, the amount nearest '
                  'the debit wording wins and balance-like numbers are ignored.',
            ),
            const _ParsingPoint(
              number: '3',
              title: 'Duplicate merge',
              body:
                  'Two alerts describing the same payment are merged into one '
                  'row, so your monthly spend counts it once.',
            ),
            const SizedBox(height: T.s2),
            Text(
              'Nothing leaves the phone at any step.',
              style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    },
  );
}

class _ParsingPoint extends StatelessWidget {
  const _ParsingPoint({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: T.primarySoft,
              borderRadius: BorderRadius.circular(T.r1),
            ),
            child: Text(
              number,
              style: T.label.copyWith(
                color: T.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: T.cardTitle.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: T.body.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
