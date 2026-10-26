import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../state/app_state.dart';

/// First-run screen. Its only job: explain the deal in one screen, then get out
/// of the way. No carousel, no sign-up, no permissions requested before the
/// reason is explained.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cream = T.inkOnPrimary;

    return Scaffold(
      // The aurora is painted by the app shell behind every route.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(T.s6, T.s5, T.s6, T.s6),
              children: [
                Row(
                  children: [
                    // The app's own logo (tool/make_logo.py), not a stock icon.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(T.r3),
                      child: Image.asset(
                        'assets/brand/logo.png',
                        width: 44,
                        height: 44,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: 'Hisaab logo',
                      ),
                    ),
                    const SizedBox(width: T.s3),
                    Text(
                      'Hisaab',
                      style: T.cardTitle.copyWith(
                        color: cream,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: T.s8),
                Text(
                  'Private by default',
                  style: T.label.copyWith(
                    color: cream.withValues(alpha: 0.78),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: T.s3),
                Text(
                  'Your money,',
                  style: T.display.copyWith(
                    color: cream,
                    fontSize: 38,
                    height: 1.08,
                  ),
                ),
                GradientText(
                  child: Text(
                    'kept honest.',
                    style: T.display.copyWith(
                      color: Colors.white,
                      fontSize: 38,
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(height: T.s4),
                Text(
                  'Hisaab reads the bank and UPI alerts already on your '
                  'phone and turns them into a clear spending picture.',
                  style: T.body.copyWith(
                    color: cream.withValues(alpha: 0.80),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: T.s5),
                Wrap(
                  spacing: T.s2,
                  runSpacing: T.s2,
                  children: [
                    _ProofChip(
                      label: 'On-device',
                      icon: Icons.phone_android_rounded,
                    ),
                    _ProofChip(
                      label: 'No sign-up',
                      icon: Icons.person_off_rounded,
                    ),
                    _ProofChip(
                      label: 'No upload',
                      icon: Icons.cloud_off_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: T.s8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.requestPermission,
                    style: FilledButton.styleFrom(
                      backgroundColor: T.teal,
                      foregroundColor: const Color(0xFF04201C),
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(T.r3),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: T.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.sms_rounded, size: 19),
                    label: const Text('Allow SMS access'),
                  ),
                ),
                const SizedBox(height: T.s2),
                Center(
                  child: TextButton(
                    onPressed: state.startDemo,
                    style: TextButton.styleFrom(
                      foregroundColor: cream.withValues(alpha: 0.9),
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('Explore with demo data'),
                  ),
                ),
                const SizedBox(height: T.s5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: cream.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: T.s1),
                    Expanded(
                      child: Text(
                        'Android asks for the SMS permission once. Nothing is '
                        'uploaded, there is no account, and you can revoke it '
                        'any time. Demo data is generated on this device.',
                        style: T.bodySmall.copyWith(
                          color: cream.withValues(alpha: 0.58),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofChip extends StatelessWidget {
  const _ProofChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cream = T.inkOnPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.s3, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(T.r5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cream.withValues(alpha: 0.72)),
          const SizedBox(width: 6),
          Text(
            label,
            style: T.bodySmall.copyWith(
              color: cream.withValues(alpha: 0.86),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
