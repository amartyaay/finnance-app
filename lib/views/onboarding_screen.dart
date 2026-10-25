import 'dart:math' as math;

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
    final cream = T.inkOnPrimary;

    return Scaffold(
      backgroundColor: T.brandDeep,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: T.onboardingGradient),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _OnboardingPatternPainter(
                    ring: Colors.white.withValues(alpha: 0.055),
                    dot: Colors.white.withValues(alpha: 0.16),
                    glow: T.mintGlow.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(T.s6, T.s5, T.s6, T.s6),
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(T.r3),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: cream,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: T.s3),
                    Text(
                      'Finance SMS',
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
                  'Your money,\nwithout the paperwork.',
                  style: T.display.copyWith(
                    color: cream,
                    fontSize: 38,
                    height: 1.03,
                  ),
                ),
                const SizedBox(height: T.s4),
                Text(
                  'Finance SMS reads the bank and UPI alerts already on your '
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
                    _ProofChip(label: 'On-device', icon: Icons.phone_android_rounded),
                    _ProofChip(label: 'No sign-up', icon: Icons.person_off_rounded),
                    _ProofChip(label: 'No upload', icon: Icons.cloud_off_rounded),
                  ],
                ),
                const SizedBox(height: T.s8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.requestPermission,
                    style: FilledButton.styleFrom(
                      backgroundColor: cream,
                      foregroundColor: T.brandDeep,
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(T.r3),
                      ),
                      textStyle: const TextStyle(
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

class _OnboardingPatternPainter extends CustomPainter {
  const _OnboardingPatternPainter({
    required this.ring,
    required this.dot,
    required this.glow,
  });

  final Color ring;
  final Color dot;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 1.02, size.height * 0.12);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(center, size.width * 0.15 * i, paint);
    }

    final dotPaint = Paint()..color = dot;
    for (var row = 0; row < 9; row++) {
      for (var col = 0; col < 5; col++) {
        final x = size.width * 0.06 + col * 18;
        final y = size.height * 0.52 + row * 18;
        if ((row + col) % 3 == 0) continue;
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [glow, glow.withValues(alpha: 0)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.15, size.height * 0.9),
          radius: size.width * 0.8,
        ),
      );
    canvas.drawRect(Offset.zero & size, glowPaint);

    // A fine arc that echoes the card faces.
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = ring;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.9, size.height * 0.8),
        radius: size.width * 0.32,
      ),
      math.pi * 0.9,
      math.pi * 0.6,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_OnboardingPatternPainter oldDelegate) =>
      oldDelegate.ring != ring ||
      oldDelegate.dot != dot ||
      oldDelegate.glow != glow;
}
