import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../domain/merchant_rule.dart';
import '../state/app_state.dart';
import 'sms_inbox_screen.dart';
import '../state/statements_controller.dart';
import 'statements_screen.dart';
import 'widgets/settings_tile.dart';
import 'widgets/txn_common.dart';

/// Settings: data, demo mode, privacy, appearance and the parser explainer.
/// The clear action never promises more than the app can keep.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const routeName = 'settings';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = T.of(context);
    final data = state.data;
    final chevron = Icon(Icons.chevron_right_rounded, color: p.inkMuted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        titleSpacing: T.s5,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
          children: [
            SoftSection(
              padding: const EdgeInsets.all(T.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    icon: Icons.lock_rounded,
                    color: p.primary,
                    size: 42,
                    iconSize: 21,
                    radius: T.r3,
                  ),
                  const SizedBox(width: T.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Private by construction',
                          style: T.cardTitle.copyWith(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No account, no upload and no analytics. Everything '
                          'here is read and kept on this phone.',
                          style: T.bodySmall.copyWith(
                            color: p.inkSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: T.s5),
            const SectionHeader(
              title: 'Data',
              padding: EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.sms_rounded,
                  title: 'Scan SMS inbox',
                  subtitle: _lastScanLabel(data.lastScanAt),
                  trailing: state.isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : chevron,
                  onTap: state.isScanning ? null : state.scanInbox,
                ),
                SettingsTile(
                  icon: Icons.account_balance_rounded,
                  title: 'Salary & statements',
                  subtitle:
                      'Import an SBI statement PDF; see each month salary to salary.',
                  trailing: chevron,
                  onTap: () => StatementsScreen.open(context),
                ),
                SettingsTile(
                  icon: Icons.forum_rounded,
                  title: 'All messages',
                  subtitle: 'Review and categorise any SMS. Optional.',
                  trailing: chevron,
                  onTap: () => SmsInboxScreen.open(context),
                ),
                const SettingsTile(
                  icon: Icons.file_upload_rounded,
                  title: 'Import CSV',
                  subtitle: 'Coming soon',
                  enabled: false,
                  trailing: Pill('Soon', dense: true),
                ),
                const SettingsTile(
                  icon: Icons.file_download_rounded,
                  title: 'Export CSV',
                  subtitle: 'Coming soon',
                  enabled: false,
                  trailing: Pill('Soon', dense: true),
                ),
                SettingsTile(
                  icon: Icons.delete_rounded,
                  title: 'Clear all data',
                  subtitle:
                      'Removes parsed alerts, statements and card settings',
                  danger: true,
                  trailing: chevron,
                  onTap: () => _confirmClear(context),
                ),
              ],
            ),
            const SizedBox(height: T.s5),
            const SectionHeader(
              title: 'Learned categories',
              subtitle: 'Rules you taught by fixing a category',
              padding: EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            const _LearnedCategories(),
            const SizedBox(height: T.s5),
            const SectionHeader(
              title: 'Demo',
              padding: EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.science_rounded,
                  title: 'Demo data',
                  subtitle:
                      'Generated on-device. Turn it off any time; your real '
                      'messages are untouched.',
                  trailing: Semantics(
                    label: 'Demo data',
                    child: Switch(
                      value: state.isDemo,
                      onChanged: (value) async {
                        await (value ? state.startDemo() : state.exitDemo());
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: T.s5),
            const SectionHeader(
              title: 'Privacy',
              padding: EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            const SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.phonelink_lock_rounded,
                  title: 'Everything on this phone',
                  subtitle:
                      'SMS is parsed on-device. Nothing is uploaded and no '
                      'account is required.',
                ),
                SettingsTile(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'Permissions',
                  subtitle: 'READ_SMS is used only to read bank alerts.',
                ),
              ],
            ),
            const SizedBox(height: T.s5),
            const SectionHeader(
              title: 'About',
              padding: EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.tag_rounded,
                  title: 'Version',
                  subtitle: 'Offline by design',
                  trailing: Text('1.0.0', style: T.body.copyWith(color: p.ink)),
                ),
                SettingsTile(
                  icon: Icons.code_rounded,
                  title: 'How parsing works',
                  subtitle: 'Sender trust, amount scoring, duplicate merge',
                  trailing: chevron,
                  onTap: () => showParsingSheet(context),
                ),
              ],
            ),
            const SizedBox(height: T.s6),
            Center(
              child: Text(
                'No account. No upload. No analytics.',
                style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final state = context.read<AppState>();
    final p = T.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear all data?'),
          content: Text(
            'This removes parsed alerts, imported bank statements, card '
            'settings and demo data from this phone. Nothing has ever been '
            'uploaded, and there is no account to delete.',
            style: T.body.copyWith(color: p.inkSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.danger,
                foregroundColor: p.isDark ? T.brandDeep : Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await state.clearAll();
    if (!context.mounted) return;
    await context.read<StatementsController>().load();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Local data cleared.')));
  }

  /// The shell may expose theming through [ThemeViewModel]. Reading it usually
  /// works, but a redesign that drops the provider should not break Settings.
}

String _lastScanLabel(DateTime? lastScanAt) {
  if (lastScanAt == null) return 'Never scanned';
  return 'Last scan ${shortDateWithYear(lastScanAt)} at '
      '${clockTime(lastScanAt)}';
}

/// The rules the owner taught by fixing a category, newest-first by use count,
/// with the undo the app has always been missing. Ten is the cap: a longer list
/// belongs on its own screen, not in Settings.
class _LearnedCategories extends StatefulWidget {
  const _LearnedCategories();

  @override
  State<_LearnedCategories> createState() => _LearnedCategoriesState();
}

class _LearnedCategoriesState extends State<_LearnedCategories> {
  static const int _maxShown = 10;

  Future<List<MerchantRule>>? _rules;
  Object? _loadedFor;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.watch<AppState>();
    // A fixed category changes the ledger, so refetch whenever it changes; the
    // list can never show a rule the undo below already deleted.
    if (!identical(state.data, _loadedFor)) {
      _loadedFor = state.data;
      _rules = state.merchantRules();
    }

    return FutureBuilder<List<MerchantRule>>(
      future: _rules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppCard(child: SkeletonBox(height: 52, radius: T.r2));
        }
        final rules = snapshot.data ?? const <MerchantRule>[];
        if (rules.isEmpty) {
          return AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  icon: Icons.school_rounded,
                  color: p.inkSecondary,
                  size: 36,
                  iconSize: 19,
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Text(
                    'Nothing learned yet — fixing a category here teaches the '
                    'app.',
                    style: T.bodySmall.copyWith(
                      color: p.inkMuted,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final shown = rules.take(_maxShown).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(T.r3),
                child: Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, indent: 64, color: p.outlineVariant),
                      _RuleRow(
                        rule: shown[i],
                        onForget: () => _forget(shown[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (rules.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: T.s2, left: T.s1),
                child: Text(
                  '${rules.length - shown.length} more learned rules not shown',
                  style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _forget(MerchantRule rule) async {
    final state = context.read<AppState>();
    final p = T.of(context);
    final label = _merchantLabel(rule);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this rule?'),
        content: Text(
          'New payments from $label will go back to the automatic category. '
          'Payments already categorised stay as they are.',
          style: T.body.copyWith(color: p.inkSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: p.danger,
              foregroundColor: p.isDark ? T.brandDeep : Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.forgetMerchantRule(rule.signature);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Forgot the rule for $label.')));
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule, required this.onForget});

  final MerchantRule rule;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final label = _merchantLabel(rule);
    final uses = rule.hits;
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: T.s4),
          child: IconBadge(
            icon: categoryIcon(rule.categoryKind),
            color: categoryColor(context, rule.categoryKind),
            size: 36,
            iconSize: 19,
          ),
        ),
        const SizedBox(width: T.s3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: T.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(color: p.ink),
                ),
                const SizedBox(height: 1),
                Text(
                  '${rule.categoryName} · $uses ${uses == 1 ? 'use' : 'uses'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(color: p.inkMuted, height: 1.35),
                ),
              ],
            ),
          ),
        ),
        // Icon-only action: the tooltip is the semantics label TalkBack reads.
        IconButton(
          onPressed: onForget,
          tooltip: 'Forget rule for $label',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(Icons.delete_outline_rounded, color: p.inkMuted),
        ),
      ],
    );
  }
}

String _merchantLabel(MerchantRule rule) {
  final merchant = rule.sampleMerchant?.trim();
  if (merchant != null && merchant.isNotEmpty) return merchant;
  return rule.signature;
}
