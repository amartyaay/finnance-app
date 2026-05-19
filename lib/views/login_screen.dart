import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/theme_view_model.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.onGooglePressed});

  final VoidCallback onGooglePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance SMS'),
        actions: const [_ThemeMenuButton()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final intro = _IntroPanel(onGooglePressed: onGooglePressed);
                  final preview = const _LoginPreviewPanel();

                  if (!isWide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        intro,
                        const SizedBox(height: 16),
                        preview,
                      ],
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: intro),
                          Container(width: 1, color: colors.outlineVariant),
                          Expanded(child: preview),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeMenuButton extends StatelessWidget {
  const _ThemeMenuButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeViewModel>(
      builder: (context, viewModel, _) {
        return PopupMenuButton<AppThemePreference>(
          tooltip: 'Theme',
          icon: const Icon(Icons.brightness_6_rounded),
          initialValue: viewModel.preference,
          onSelected: viewModel.setPreference,
          itemBuilder: (context) {
            return AppThemePreference.values
                .map(
                  (preference) => CheckedPopupMenuItem<AppThemePreference>(
                    value: preference,
                    checked: viewModel.preference == preference,
                    child: Text(viewModel.labelFor(preference)),
                  ),
                )
                .toList(growable: false);
          },
        );
      },
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({required this.onGooglePressed});

  final VoidCallback onGooglePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Track Indian spends from SMS',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sign in with Google to view your finance workspace across mobile and web. SMS scanning remains Android-only.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onGooglePressed,
              icon: const _GoogleMark(),
              label: const Text('Continue with Google'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No email/password login is available in this UI.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        'G',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LoginPreviewPanel extends StatelessWidget {
  const _LoginPreviewPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Account preview', style: theme.textTheme.titleMedium),
          const SizedBox(height: 14),
          _PreviewMetric(
            icon: Icons.payments_rounded,
            label: 'May spend',
            value: 'Rs. 42,850',
          ),
          const SizedBox(height: 10),
          _PreviewMetric(
            icon: Icons.credit_card_rounded,
            label: 'Cards detected',
            value: '3 active',
          ),
          const SizedBox(height: 10),
          _PreviewMetric(
            icon: Icons.category_rounded,
            label: 'Top category',
            value: 'Food',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _PreviewChip(label: 'UPI'),
              _PreviewChip(label: 'Cards'),
              _PreviewChip(label: 'Local first'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.check_rounded, size: 16),
      label: Text(label),
    );
  }
}
