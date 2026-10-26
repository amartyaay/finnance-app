// Three Home-screen design concepts, rendered on the demo data so the owner can
// pick a direction before the full rebuild:
//
//   flutter test test_visual/concepts_test.dart   -> docs/shots/concept-*.png
//
// All three share one information design (de-cluttered): the month's spend
// with one line of context, three numbers, one chart, top categories, recent
// payments, and every alert folded into one row. They differ only in style.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/data/finance_repository.dart';
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/money.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

final DateTime _now = DateTime(2026, 6, 15, 12);
const _font = 'Inter';

Future<void> _loadFonts() async {
  final inter = FontLoader(_font);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(_bytes('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final pub = '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/phosphor_flutter-2.1.0/lib/fonts';
  for (final (style, file) in [('Regular', 'Phosphor'), ('Fill', 'Phosphor-Fill'), ('Bold', 'Phosphor-Bold'), ('Duotone', 'Phosphor-Duotone')]) {
    await (FontLoader('packages/phosphor_flutter/Phosphor$style')..addFont(_bytes('$pub/$file.ttf'))).load();
  }
}

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(File(path).readAsBytesSync());

// ---- shared data helpers ----------------------------------------------------

String rs(int paise) => inr(Paise((paise / 100).round() * 100));
String rsK(int paise) => inrCompact(Paise(paise));

List<double> cumulative(List<int> daily) {
  var run = 0;
  return [for (final d in daily) (run += d) / 100.0];
}

List<Txn> recent(HomeData d) => ([...d.transactions]
      ..sort((a, b) => b.occurredAtMs.compareTo(a.occurredAtMs)))
    .where((t) => t.kind == TxnKind.spend)
    .take(4)
    .toList();

IconData kindIcon(SpendCategoryKind k) => switch (k) {
  SpendCategoryKind.food => PhosphorIconsFill.forkKnife,
  SpendCategoryKind.groceries => PhosphorIconsFill.shoppingCart,
  SpendCategoryKind.transport => PhosphorIconsFill.car,
  SpendCategoryKind.shopping => PhosphorIconsFill.bag,
  SpendCategoryKind.bills => PhosphorIconsFill.receipt,
  SpendCategoryKind.rent => PhosphorIconsFill.house,
  SpendCategoryKind.travel => PhosphorIconsFill.airplaneTilt,
  SpendCategoryKind.health => PhosphorIconsFill.heartbeat,
  SpendCategoryKind.entertainment => PhosphorIconsFill.filmSlate,
  _ => PhosphorIconsFill.circlesFour,
};

String alertsLine(HomeData d) {
  final n = d.phishingAlerts.length + d.unpaidBillCount + (d.needsReviewCount > 0 ? 1 : 0);
  return '$n things need you';
}

TextStyle ts(double size, Color c, {FontWeight w = FontWeight.w500, double ls = 0, double h = 1.2}) =>
    TextStyle(fontFamily: _font, fontSize: size, color: c, fontWeight: w, letterSpacing: ls, height: h,
        fontFeatures: const [FontFeature.tabularFigures()]);

// =============================================================================
// A · Noir & Lime
// =============================================================================
class ConceptNoir extends StatelessWidget {
  const ConceptNoir(this.d, {super.key});
  final HomeData d;

  static const bg = Color(0xFF0B0B0C);
  static const card = Color(0xFF161618);
  static const lime = Color(0xFFD4FF3F);
  static const ink = Color(0xFFF5F5F2);
  static const mute = Color(0xFF8C8C93);

  @override
  Widget build(BuildContext context) {
    final s = d.summary;
    final cur = cumulative(s.dailySpend);
    final prev = cumulative(d.previousSummary.dailySpend);
    final top = math.max(cur.isEmpty ? 0.0 : cur.last, prev.isEmpty ? 0.0 : prev.last) * 1.08;
    final change = s.previousSpendPaise == 0 ? 0 : ((s.spendPaise - s.previousSpendPaise) / s.previousSpendPaise * 100).round();
    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 120),
          children: [
            Row(children: [
              const CircleAvatar(radius: 20, backgroundColor: card, child: Text('A', style: TextStyle(fontFamily: _font, color: lime, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
              Expanded(child: Text('Hi Amartya', style: ts(16, ink, w: FontWeight.w600))),
              _round(PhosphorIconsRegular.bell, dot: true),
            ]),
            const SizedBox(height: 34),
            Text('Spent in June', style: ts(14, mute)),
            const SizedBox(height: 6),
            Text(rs(s.spendPaise), style: ts(52, ink, w: FontWeight.w700, ls: -2.2, h: 1.0)),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: lime, borderRadius: BorderRadius.circular(99)),
                child: Text('${change >= 0 ? '+' : ''}$change% vs May', style: ts(12.5, bg, w: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text('On pace for ${rsK(s.projectedSpendPaise)}', style: ts(13, mute)),
            ]),
            const SizedBox(height: 26),
            SizedBox(
              height: 150,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: top,
                minX: 0,
                maxX: (s.daysInMonth - 1).toDouble(),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < prev.length; i++) FlSpot(i.toDouble(), prev[i])],
                    isCurved: true, barWidth: 1.5, color: mute.withValues(alpha: 0.5),
                    dashArray: [4, 4], dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: [for (var i = 0; i < cur.length; i++) FlSpot(i.toDouble(), cur[i])],
                    isCurved: true, curveSmoothness: 0.25, barWidth: 3, color: lime,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, bar) => spot.x == cur.length - 1,
                      getDotPainter: (a, b, c, e) => FlDotCirclePainter(radius: 5, color: lime, strokeWidth: 4, strokeColor: lime.withValues(alpha: 0.25)),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [lime.withValues(alpha: 0.28), lime.withValues(alpha: 0)]),
                    ),
                  ),
                ],
              )),
            ),
            const SizedBox(height: 6),
            Row(children: [Text('1 Jun', style: ts(11.5, mute)), const Spacer(), Text('--- May', style: ts(11.5, mute))]),
            const SizedBox(height: 28),
            Row(children: [
              _stat('Came in', rsK(s.incomePaise)),
              _divider(),
              _stat('Went out', rsK(s.moneyOutPaise)),
              _divider(),
              _stat('Left', rsK(s.leftPaise), accent: true),
            ]),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                const Icon(PhosphorIconsFill.warningCircle, color: lime, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(alertsLine(d), style: ts(15, ink, w: FontWeight.w600))),
                Text('1 fraud · 2 bills', style: ts(12.5, mute)),
                const SizedBox(width: 6),
                const Icon(PhosphorIconsRegular.caretRight, color: mute, size: 18),
              ]),
            ),
            const SizedBox(height: 30),
            Text('Where it went', style: ts(18, ink, w: FontWeight.w700, ls: -0.3)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(height: 10, child: Row(children: [
                for (final (i, c) in s.byCategory.take(5).indexed)
                  Expanded(flex: (c.share * 1000).round().clamp(1, 1000), child: Container(
                    margin: const EdgeInsets.only(right: 3),
                    color: [lime, const Color(0xFFB8E0FF), const Color(0xFFFFB4A2), const Color(0xFFC9B6FF), const Color(0xFF7D7D85)][i],
                  )),
              ])),
            ),
            const SizedBox(height: 14),
            for (final (i, c) in s.byCategory.take(4).indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
                      color: [lime, const Color(0xFFB8E0FF), const Color(0xFFFFB4A2), const Color(0xFFC9B6FF)][i])),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.name, style: ts(15, ink))),
                  Text('${(c.share * 100).round()}%', style: ts(13, mute)),
                  const SizedBox(width: 14),
                  SizedBox(width: 86, child: Text(rs(c.paise), textAlign: TextAlign.right, style: ts(15, ink, w: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 22),
            Text('Recent', style: ts(18, ink, w: FontWeight.w700, ls: -0.3)),
            const SizedBox(height: 8),
            for (final t in recent(d))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: const BoxDecoration(color: card, shape: BoxShape.circle),
                      child: Icon(kindIcon(t.categoryKind), color: ink, size: 20)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.merchant ?? 'Payment', style: ts(15, ink, w: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${t.categoryName ?? ''} · ${DateFormat('d MMM').format(t.occurredAt)}', style: ts(12.5, mute)),
                  ])),
                  Text('−${rs(t.amountPaise)}', style: ts(15, ink, w: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, {bool dot = false}) => Stack(children: [
        Container(width: 42, height: 42, decoration: const BoxDecoration(color: card, shape: BoxShape.circle),
            child: Icon(icon, color: ink, size: 20)),
        if (dot) Positioned(right: 10, top: 10, child: Container(width: 8, height: 8,
            decoration: const BoxDecoration(color: lime, shape: BoxShape.circle))),
      ]);

  Widget _stat(String label, String value, {bool accent = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(12.5, mute)),
          const SizedBox(height: 5),
          Text(value, style: ts(20, accent ? lime : ink, w: FontWeight.w700, ls: -0.5)),
        ]),
      );

  Widget _divider() => Container(width: 1, height: 38, margin: const EdgeInsets.symmetric(horizontal: 14), color: const Color(0xFF26262A));
}

class NoirNav extends StatelessWidget {
  const NoirNav({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 84,
        padding: const EdgeInsets.only(bottom: 18),
        decoration: const BoxDecoration(color: ConceptNoir.bg, border: Border(top: BorderSide(color: Color(0xFF1E1E21)))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final (i, icon) in [PhosphorIconsFill.house, PhosphorIconsRegular.listBullets, PhosphorIconsRegular.creditCard, PhosphorIconsRegular.sparkle].indexed)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: i == 0 ? ConceptNoir.lime : ConceptNoir.mute, size: 26),
              const SizedBox(height: 6),
              Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: i == 0 ? ConceptNoir.lime : Colors.transparent)),
            ]),
        ]),
      );
}

// =============================================================================
// B · Paper & Green
// =============================================================================
class ConceptPaper extends StatelessWidget {
  const ConceptPaper(this.d, {super.key});
  final HomeData d;

  static const bg = Color(0xFFF4F3EE);
  static const green = Color(0xFF9FE870);
  static const forest = Color(0xFF163300);
  static const ink = Color(0xFF16181A);
  static const mute = Color(0xFF6B6F6A);

  @override
  Widget build(BuildContext context) {
    final s = d.summary;
    final daily = s.dailySpend;
    final maxDay = daily.isEmpty ? 1 : daily.reduce(math.max);
    final palette = [forest, const Color(0xFF4F7A28), const Color(0xFF9FE870), const Color(0xFFCFE9B6), const Color(0xFFBDBDB4)];
    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Good afternoon', style: ts(14, mute)),
                Text('Amartya', style: ts(26, ink, w: FontWeight.w800, ls: -0.8)),
              ])),
              Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(PhosphorIconsBold.bell, color: ink, size: 20)),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(28)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Spent in June', style: ts(15, forest, w: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(rs(s.spendPaise), style: ts(46, forest, w: FontWeight.w800, ls: -2, h: 1.0)),
                const SizedBox(height: 8),
                Text('On pace for ${rs(s.projectedSpendPaise)} · ${s.daysElapsed} of ${s.daysInMonth} days', style: ts(13.5, forest.withValues(alpha: 0.75))),
                const SizedBox(height: 18),
                SizedBox(
                  height: 64,
                  child: BarChart(BarChartData(
                    maxY: maxDay / 100.0,
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                    barGroups: [
                      for (var i = 0; i < s.daysInMonth; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: i < daily.length ? math.max(daily[i] / 100.0, maxDay / 100.0 * 0.015) : maxDay / 100.0 * 0.015,
                            width: 6,
                            color: i < daily.length && daily[i] > 0 ? forest : forest.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ]),
                    ],
                  )),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _chip('Came in', rsK(s.incomePaise), PhosphorIconsBold.arrowDownLeft),
              const SizedBox(width: 10),
              _chip('Went out', rsK(s.moneyOutPaise), PhosphorIconsBold.arrowUpRight),
              const SizedBox(width: 10),
              _chip('Left', rsK(s.leftPaise), PhosphorIconsBold.piggyBank),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                const Icon(PhosphorIconsFill.bellRinging, color: green, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(alertsLine(d), style: ts(15, Colors.white, w: FontWeight.w600))),
                const Icon(PhosphorIconsBold.caretRight, color: green, size: 18),
              ]),
            ),
            const SizedBox(height: 26),
            Text('Where it went', style: ts(20, ink, w: FontWeight.w800, ls: -0.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                SizedBox(
                  width: 120, height: 120,
                  child: Stack(alignment: Alignment.center, children: [
                    PieChart(PieChartData(
                      sectionsSpace: 3, centerSpaceRadius: 40, startDegreeOffset: -90,
                      sections: [
                        for (final (i, c) in s.byCategory.take(5).indexed)
                          PieChartSectionData(value: c.share, color: palette[i], radius: 16, showTitle: false),
                      ],
                    )),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(rsK(s.spendPaise), style: ts(15, ink, w: FontWeight.w800)),
                      Text('June', style: ts(11, mute)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 18),
                Expanded(child: Column(children: [
                  for (final (i, c) in s.byCategory.take(4).indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[i], borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, ink))),
                        Text(rsK(c.paise), style: ts(13.5, ink, w: FontWeight.w700)),
                      ]),
                    ),
                ])),
              ]),
            ),
            const SizedBox(height: 26),
            Text('Recent', style: ts(20, ink, w: FontWeight.w800, ls: -0.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(children: [
                for (final t in recent(d))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Container(width: 42, height: 42, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                          child: Icon(kindIcon(t.categoryKind), color: forest, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.merchant ?? 'Payment', style: ts(15, ink, w: FontWeight.w700)),
                        Text(t.categoryName ?? '', style: ts(12.5, mute)),
                      ])),
                      Text(rs(t.amountPaise), style: ts(15, ink, w: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: forest),
            const SizedBox(height: 8),
            Text(value, style: ts(17, ink, w: FontWeight.w800, ls: -0.4)),
            Text(label, style: ts(12, mute)),
          ]),
        ),
      );
}

class PaperNav extends StatelessWidget {
  const PaperNav({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          height: 66,
          decoration: BoxDecoration(color: ConceptPaper.forest, borderRadius: BorderRadius.circular(33)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: ConceptPaper.green, borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                const Icon(PhosphorIconsFill.house, color: ConceptPaper.forest, size: 20),
                const SizedBox(width: 6),
                Text('Home', style: ts(14, ConceptPaper.forest, w: FontWeight.w700)),
              ]),
            ),
            for (final icon in [PhosphorIconsBold.listBullets, PhosphorIconsBold.creditCard, PhosphorIconsBold.sparkle])
              Icon(icon, color: Colors.white.withValues(alpha: 0.75), size: 22),
          ]),
        ),
      );
}

// =============================================================================
// C · Aurora Glass
// =============================================================================
class ConceptAurora extends StatelessWidget {
  const ConceptAurora(this.d, {super.key});
  final HomeData d;

  static const bg = Color(0xFF060A14);
  static const ink = Color(0xFFF2F6FF);
  static const mute = Color(0xFF93A0BE);
  static const teal = Color(0xFF2DD4BF);
  static const blue = Color(0xFF60A5FA);
  static const violet = Color(0xFFA78BFA);

  @override
  Widget build(BuildContext context) {
    final s = d.summary;
    final daily = s.dailySpend;
    final maxDay = daily.isEmpty ? 1 : daily.reduce(math.max);
    return Stack(children: [
      const Positioned.fill(child: ColoredBox(color: bg)),
      Positioned(top: -120, left: -80, child: _blob(teal, 320)),
      Positioned(top: 40, right: -140, child: _blob(violet, 340)),
      Positioned(top: 520, left: -120, child: _blob(blue, 300)),
      Positioned.fill(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70), child: const SizedBox())),
      SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(children: [
              Text('June 2026', style: ts(24, ink, w: FontWeight.w800, ls: -0.6)),
              const Spacer(),
              _glass(const Padding(padding: EdgeInsets.all(11), child: Icon(PhosphorIconsRegular.bell, color: ink, size: 20)), radius: 99),
            ]),
            const SizedBox(height: 20),
            _glass(Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Spent this month', style: ts(14, mute)),
                const SizedBox(height: 6),
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [teal, blue, violet]).createShader(r),
                  child: Text(rs(s.spendPaise), style: ts(48, Colors.white, w: FontWeight.w800, ls: -2, h: 1.0)),
                ),
                const SizedBox(height: 8),
                Text('On pace for ${rs(s.projectedSpendPaise)}', style: ts(13.5, mute)),
                const SizedBox(height: 18),
                SizedBox(
                  height: 70,
                  child: BarChart(BarChartData(
                    maxY: maxDay / 100.0,
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                    barGroups: [
                      for (var i = 0; i < s.daysInMonth; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: i < daily.length ? math.max(daily[i] / 100.0, maxDay / 100.0 * 0.015) : maxDay / 100.0 * 0.015,
                            width: 5,
                            gradient: i < daily.length
                                ? const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [teal, blue])
                                : null,
                            color: i < daily.length ? null : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ]),
                    ],
                  )),
                ),
              ]),
            )),
            const SizedBox(height: 12),
            Row(children: [
              _stat('Came in', rsK(s.incomePaise), teal),
              const SizedBox(width: 10),
              _stat('Went out', rsK(s.moneyOutPaise), blue),
              const SizedBox(width: 10),
              _stat('Left', rsK(s.leftPaise), violet),
            ]),
            const SizedBox(height: 12),
            _glass(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                const Icon(PhosphorIconsDuotone.shieldWarning, color: Color(0xFFFDA4AF), size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text(alertsLine(d), style: ts(15, ink, w: FontWeight.w600))),
                const Icon(PhosphorIconsRegular.caretRight, color: mute, size: 18),
              ]),
            )),
            const SizedBox(height: 24),
            Text('Where it went', style: ts(18, ink, w: FontWeight.w700, ls: -0.3)),
            const SizedBox(height: 12),
            _glass(Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                for (final (i, c) in s.byCategory.take(4).indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(kindIcon(c.kind), color: [teal, blue, violet, const Color(0xFFFDA4AF)][i], size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c.name, style: ts(14.5, ink, w: FontWeight.w600))),
                          Text(rs(c.paise), style: ts(14.5, ink, w: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: c.share, minHeight: 5,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            color: [teal, blue, violet, const Color(0xFFFDA4AF)][i],
                          ),
                        ),
                      ])),
                    ]),
                  ),
              ]),
            )),
          ],
        ),
      ),
    ]);
  }

  static Widget _blob(Color c, double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.38)),
      );

  static Widget _glass(Widget child, {double radius = 24}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: child,
          ),
        ),
      );

  Widget _stat(String label, String value, Color c) => Expanded(
        child: _glass(Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(height: 10),
            Text(value, style: ts(17, ink, w: FontWeight.w800, ls: -0.4)),
            Text(label, style: ts(12, mute)),
          ]),
        ), radius: 20),
      );
}

class AuroraNav extends StatelessWidget {
  const AuroraNav({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: ConceptAurora._glass(SizedBox(
          height: 64,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final (i, icon) in [PhosphorIconsFill.house, PhosphorIconsRegular.listBullets, PhosphorIconsRegular.creditCard, PhosphorIconsRegular.sparkle].indexed)
              Icon(icon, color: i == 0 ? ConceptAurora.teal : ConceptAurora.mute, size: 24),
          ]),
        ), radius: 32),
      );
}

// =============================================================================

final GlobalKey _boundary = GlobalKey();

Future<void> _render(WidgetTester tester, String name, Widget page, Widget nav, Color bg) async {
  await tester.pumpWidget(RepaintBoundary(
    key: _boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: _font),
      home: Scaffold(backgroundColor: bg, extendBody: true, body: page, bottomNavigationBar: nav),
    ),
  ));
  await tester.pumpAndSettle();
  final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  File('docs/shots/concept-$name.png').writeAsBytesSync(bytes!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  testWidgets('concepts', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    try {
      final data = (await tester.runAsync(() => DemoFinanceRepository(now: _now).load()))!;
      await _render(tester, 'a-noir', ConceptNoir(data), const NoirNav(), ConceptNoir.bg);
      await _render(tester, 'b-paper', ConceptPaper(data), const PaperNav(), ConceptPaper.bg);
      await _render(tester, 'c-aurora', ConceptAurora(data), const AuroraNav(), ConceptAurora.bg);
    } finally {
      debugDisableShadows = true;
    }
  });
}
