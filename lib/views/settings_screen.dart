import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../state/app_state.dart';
import '../viewmodels/theme_view_model.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final data = state.data;
    final themeController = _themeController(context);
    final chevron = Icon(
      Icons.chevron_right_rounded,
      color: scheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), titleSpacing: T.s5),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
          children: [
            Text(
              'Everything here stays on this phone. There is no account, no '
              'upload and no analytics.',
              style: T.body.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: T.s6),
            const SectionHeader(title: 'Data'),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.sms_outlined,
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
                const SettingsTile(
                  icon: Icons.file_upload_outlined,
                  title: 'Import CSV',
                  subtitle: 'Coming soon',
                  enabled: false,
                  trailing: Pill('Soon', dense: true),
                ),
                const SettingsTile(
                  icon: Icons.file_download_outlined,
                  title: 'Export CSV',
                  subtitle: 'Coming soon',
                  enabled: false,
                  trailing: Pill('Soon', dense: true),
                ),
                SettingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Clear all data',
                  subtitle: 'Removes parsed alerts and card settings',
                  danger: true,
                  trailing: chevron,
                  onTap: () => _confirmClear(context),
                ),
              ],
            ),
            const SizedBox(height: T.s5),
            const SectionHeader(title: 'Demo'),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.science_outlined,
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
            const SectionHeader(title: 'Privacy'),
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
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Permissions',
                  subtitle: 'READ_SMS is used only to read bank alerts.',
                ),
              ],
            ),
            // The shell owns theming. If a redesign swaps that controller out,
            // settings loses the control instead of crashing the screen.
            if (themeController != null) ...[
              const SizedBox(height: T.s5),
              const SectionHeader(title: 'Appearance'),
              AppCard(
                padding: const EdgeInsets.all(T.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme',
                      style: T.cardTitle.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'System follows your phone. Light and dark apply '
                      'everywhere.',
                      style: T.bodySmall.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: T.s3),
                    SegmentedButton<AppThemePreference>(
                      segments: const [
                        ButtonSegment<AppThemePreference>(
                          value: AppThemePreference.system,
                          label: Text('System'),
                        ),
                        ButtonSegment<AppThemePreference>(
                          value: AppThemePreference.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment<AppThemePreference>(
                          value: AppThemePreference.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {themeController.preference},
                      showSelectedIcon: false,
                      expandedInsets: EdgeInsets.zero,
                      onSelectionChanged: (selection) =>
                          themeController.setPreference(selection.first),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: T.s5),
            const SectionHeader(title: 'About'),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.tag_rounded,
                  title: 'Version',
                  subtitle: 'Offline by design',
                  trailing: Text(
                    '1.0.0',
                    style: T.body.copyWith(color: scheme.onSurface),
                  ),
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
            const SizedBox(height: T.s5),
            Center(
              child: Text(
                'No account. No upload. No analytics.',
                style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final state = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear all data?'),
          content: Text(
            'This removes parsed alerts, card settings and demo data from '
            'this phone. Nothing has ever been uploaded, and there is no '
            'account to delete.',
            style: T.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: T.danger,
                foregroundColor: Colors.white,
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local data stays on this phone.')),
    );
  }

  /// The shell may expose theming through [ThemeViewModel]. Reading it usually
  /// works, but a redesign that drops the provider should not break Settings.
  ThemeViewModel? _themeController(BuildContext context) {
    try {
      return context.watch<ThemeViewModel>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

String _lastScanLabel(DateTime? lastScanAt) {
  if (lastScanAt == null) return 'Never scanned';
  return 'Last scan ${shortDateWithYear(lastScanAt)} at '
      '${clockTime(lastScanAt)}';
}
