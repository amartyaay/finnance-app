import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../state/app_state.dart';

/// First-run screen. Its only job: explain the deal in one screen, then get out
/// of the way. No carousel, no sign-up, no permissions requested before the
/// reason is explained.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.s5, T.s7, T.s5, T.s7),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: T.heroGradient,
                borderRadius: BorderRadius.circular(T.r4),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: T.s6),
            Text(
              'Your spending, without the paperwork',
              style: T.display.copyWith(fontSize: 34, color: scheme.onSurface),
            ),
            const SizedBox(height: T.s3),
            Text(
              'Finance SMS reads the bank and UPI alerts already on your phone and '
              'turns them into a clean spending picture. No bank login, no account, '
              'no cloud.',
              style: T.body.copyWith(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: T.s7),
            const _Point(
              icon: Icons.offline_bolt_rounded,
              title: 'Parsed on this phone',
              body:
                  'Messages are read and classified on-device. Nothing is uploaded, '
                  'and there is no sign-up.',
            ),
            const _Point(
              icon: Icons.shield_outlined,
              title: 'Fraud messages are flagged',
              body:
                  'Fake KYC, refund and parcel scams are detected and kept away from '
                  'your totals.',
            ),
            const _Point(
              icon: Icons.credit_card_rounded,
              title: 'Card utilisation, done right',
              body:
                  'See how much of each card limit is used, before the statement date, '
                  'not after.',
            ),
            const SizedBox(height: T.s7),
            FilledButton.icon(
              onPressed: state.requestPermission,
              icon: const Icon(Icons.sms_rounded, size: 18),
              label: const Text('Allow SMS access'),
            ),
            const SizedBox(height: T.s3),
            Center(
              child: Text(
                'Android asks for the SMS permission once. You can revoke it any time '
                'in system settings.',
                textAlign: TextAlign.center,
                style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: T.s6),
            OutlinedButton(
              onPressed: state.startDemo,
              child: const Text('Explore with demo data'),
            ),
            const SizedBox(height: T.s2),
            Center(
              child: Text(
                'Demo data is generated on this device and can be removed any time.',
                textAlign: TextAlign.center,
                style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(T.r2),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.cardTitle.copyWith(color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text(body, style: T.body.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
