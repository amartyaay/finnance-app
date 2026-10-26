import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../domain/money.dart';
import '../domain/statement.dart';
import '../engine/salary_cycles.dart';
import '../services/statement/pdf_words.dart';
import '../state/statements_controller.dart';
import 'salary_cycle_screen.dart';
import 'widgets/salary_cycle_card.dart';

/// Bank statements: import an SBI statement PDF (with its password), find the
/// salary, and show spending salary to salary.
///
/// Everything happens on the phone. The password opens the file once and is
/// not kept; the picked copy of the file is deleted after reading.
class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key});

  static const String routeName = 'statements';

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const StatementsScreen(),
    ),
  );

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<StatementsController>().load();
    });
  }

  Future<void> _import() async {
    final controller = context.read<StatementsController>();
    final messenger = ScaffoldMessenger.of(context);
    final ({String path, String name})? picked;
    try {
      picked = await controller.pickPdf();
    } catch (e) {
      if (mounted) _showFailure('Could not open the file picker', e);
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _importing = true);
    try {
      String? password;
      StatementPreview? preview;
      String? error;
      while (preview == null) {
        try {
          preview = await controller.preview(
            picked.path,
            picked.name,
            password: password,
          );
        } on PdfNeedsPassword {
          error = null;
        } on PdfWrongPassword {
          error = 'That password did not open the file. Check the hints below.';
        } on PdfUnreadable {
          messenger.showSnackBar(
            const SnackBar(content: Text('This file is not a readable PDF.')),
          );
          return;
        }
        // Anything else (the PDF engine failing to start, a file the picker
        // could not copy) used to vanish silently; now it is shown.
        catch (e) {
          if (mounted) _showFailure('Could not read this statement', e);
          return;
        }
        if (preview != null) break;
        if (!mounted) return;
        password = await showStatementPasswordSheet(
          context,
          fileName: picked.name,
          error: error,
        );
        if (password == null) return; // cancelled
      }
      if (!mounted) return;
      if (preview.statement.rows.isEmpty) {
        final layout = preview.layout;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No transactions found'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layout.contains('no text layer')
                        ? 'This PDF is a scanned image with no text in it, so '
                              'it cannot be read. Download the statement again '
                              'from OnlineSBI or YONO as a PDF.'
                        : "The file opened, but its table layout isn't one "
                              'Hisaab knows yet. Copy the details below and '
                              'send them over: they hold only the column '
                              'labels and counts, never amounts or names.',
                  ),
                  const SizedBox(height: T.s3),
                  SelectableText(
                    layout,
                    style: T.bodySmall.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: layout));
                  Navigator.pop(context);
                },
                child: const Text('Copy details'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await showStatementReviewSheet(context, preview);
      if (confirmed != true || !mounted) return;
      final result = await controller.commit(preview);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.sameFile
                ? 'This statement was already imported.'
                : result.alreadyKnown > 0
                ? '${result.added} new transactions added '
                      '(${result.alreadyKnown} were already there).'
                : '${result.added} transactions imported.',
          ),
        ),
      );
    } finally {
      await controller.discardPickedFiles();
      if (mounted) setState(() => _importing = false);
    }
  }

  /// The error's type and message, never the password (it is not in any
  /// exception this flow raises).
  void _showFailure(String title, Object error) {
    final details = '${error.runtimeType}: $error';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText(
            details.length > 600 ? details.substring(0, 600) : details,
            style: T.bodySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: details));
              Navigator.pop(context);
            },
            child: const Text('Copy details'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<StatementsController>();
    final p = T.of(context);
    final account = controller.selected;
    final analysis = controller.analysis;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: T.s5,
        title: const Text('Salary & statements'),
        actions: [
          if (account != null)
            IconButton(
              tooltip: 'Import another statement',
              icon: const Icon(Icons.upload_file_rounded),
              onPressed: _importing ? null : _import,
            ),
        ],
      ),
      body: Stack(
        children: [
          if (!controller.hasLoaded)
            const Center(child: CircularProgressIndicator())
          else if (account == null)
            _EmptyImport(onImport: _importing ? null : _import)
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, T.s8),
              children: [
                _AccountHeader(controller: controller),
                const SizedBox(height: T.s4),
                if (analysis != null) ...[
                  _SalaryCard(verdict: analysis.salary, rows: controller.rows),
                  const SizedBox(height: T.s5),
                  SectionHeader(
                    title: 'Salary to salary',
                    subtitle: analysis.salary.found
                        ? 'Each cycle runs from one salary to the next.'
                        : 'No salary found yet, so this is the whole statement.',
                  ),
                  for (final cycle in _ordered(analysis.cycles)) ...[
                    SalaryCycleCard(
                      cycle: cycle,
                      onTap: () => SalaryCycleScreen.open(context, cycle),
                    ),
                    const SizedBox(height: T.s3),
                  ],
                ],
                const SizedBox(height: T.s3),
                Text(
                  'Read on this phone only. The file and its password never '
                  'leave the device, and the password is not saved.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          if (_importing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}

class _EmptyImport extends StatelessWidget {
  const _EmptyImport({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s5, T.s6, T.s5, T.s8),
      children: [
        EmptyState(
          icon: Icons.account_balance_rounded,
          title: 'See every month, salary to salary',
          body:
              'Import an SBI account statement (PDF). We find your salary, then '
              'show where the money went between one payday and the next. '
              'Statements catch what SMS miss: most SBI debits never send an alert.',
          actionLabel: 'Choose statement PDF',
          onAction: onImport,
        ),
        const SizedBox(height: T.s5),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where to get it',
                style: T.cardTitle.copyWith(color: p.ink),
              ),
              const SizedBox(height: T.s2),
              for (final line in const [
                'YONO › Accounts › Statement › Download PDF',
                'OnlineSBI › My Accounts › Account Statement › PDF',
                'The monthly e-statement email from SBI (password-protected)',
              ])
                Padding(
                  padding: const EdgeInsets.only(top: T.s1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: T.body.copyWith(color: p.inkMuted)),
                      Expanded(
                        child: Text(
                          line,
                          style: T.body.copyWith(color: p.inkSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: T.s3),
              Text(
                'Read on this phone only. The file and its password never leave '
                'the device, and the password is not saved.',
                style: T.bodySmall.copyWith(color: p.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Newest first, except that a running cycle only a few days old goes after
/// the last complete one: "1 Oct – 1 Oct, 1 day, left ₹1,12,450" is not the
/// first thing anyone wants to read.
List<SalaryCycle> _ordered(List<SalaryCycle> cycles) {
  if (cycles.length < 2) return cycles;
  final first = cycles.first;
  if (first.isPartial && first.salaryRows.isNotEmpty && first.days < 7) {
    return [cycles[1], first, ...cycles.skip(2)];
  }
  return cycles;
}

String _range(DateTime? from, DateTime? to) {
  if (from == null || to == null) return '';
  final f = DateFormat('d MMM yyyy');
  return '${f.format(from)} – ${f.format(to)}';
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.controller});

  final StatementsController controller;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final a = controller.selected!;
    final allVerified = a.verified == a.rows;
    return AppCard(
      child: Row(
        children: [
          IconBadge(icon: Icons.account_balance_rounded, color: p.primary),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${a.bank} savings ${a.accountMask == null ? '' : '•• ${a.accountMask}'}',
                  style: T.cardTitle.copyWith(color: p.ink),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _range(a.from, a.to),
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
                const SizedBox(height: T.s2),
                Wrap(
                  spacing: T.s2,
                  runSpacing: T.s1,
                  children: [
                    Pill('${a.rows} transactions', dense: true),
                    Pill(
                      allVerified
                          ? 'All balances check out'
                          : '${a.verified} of ${a.rows} balances check out',
                      tone: allVerified ? PillTone.positive : PillTone.caution,
                      icon: allVerified
                          ? Icons.verified_rounded
                          : Icons.error_outline_rounded,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Statement options',
            onSelected: (value) async {
              if (value != 'delete') return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Remove imported statements?'),
                  content: const Text(
                    'This deletes the imported transactions for this account from '
                    'the app. Your SMS and the PDF itself are not touched.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
              if (ok == true) await controller.deleteAccount(a.accountKey);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('Remove imported statements'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SalaryCard extends StatelessWidget {
  const _SalaryCard({required this.verdict, required this.rows});

  final SalaryVerdict verdict;
  final List<StatementRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    if (!verdict.found) {
      return NoticeBanner(
        title: 'No salary found yet',
        body:
            'Open a cycle and tap a credit to mark it as your salary. '
            'Cycles will then run from payday to payday.',
        icon: Icons.payments_rounded,
      );
    }
    // The salary is this screen's hero: one number, who pays it, and why
    // the app believes it.
    return HeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded, size: 16, color: p.heroMuted),
              const SizedBox(width: T.s2),
              Text(
                'Your salary',
                style: T.label.copyWith(color: p.heroMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: T.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: GradientText(
              child: MoneyText(
                Paise(verdict.typicalPaise),
                style: T.heroNumber.copyWith(fontSize: 40, color: Colors.white),
              ),
            ),
          ),
          if (verdict.payer != null) ...[
            const SizedBox(height: T.s1),
            Text(
              'from ${verdict.payer}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body.copyWith(
                color: p.heroInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: T.s3),
          Text(
            '${verdict.reason} Not right? Open a cycle and tap the credit.',
            style: T.bodySmall.copyWith(color: p.heroMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Asks for the PDF's password. Returns null when the user cancels.
Future<String?> showStatementPasswordSheet(
  BuildContext context, {
  required String fileName,
  String? error,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      top: false,
      child: _PasswordSheet(fileName: fileName, error: error),
    ),
  );
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.fileName, this.error});

  final String fileName;
  final String? error;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _password.text;
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This statement is locked',
              style: T.title.copyWith(color: p.ink),
            ),
            const SizedBox(height: T.s1),
            Text(
              widget.fileName,
              style: T.bodySmall.copyWith(color: p.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: T.s4),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              inputFormatters: [LengthLimitingTextInputFormatter(64)],
              decoration: InputDecoration(
                labelText: 'PDF password',
                errorText: widget.error,
                errorMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: T.s2),
            Text(
              'Used once to open the file on this phone. Never saved or sent anywhere.',
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: T.s3),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: T.s2),
                title: Text(
                  'How do I find my password?',
                  style: T.label.copyWith(color: p.primary),
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (where, rule) in const [
                    (
                      'SBI e-statement email',
                      'Last 5 digits of your registered mobile + date of birth as DDMMYY. Example: 98765150890',
                    ),
                    (
                      'YONO download',
                      'Usually your date of birth as DDMMYYYY. Example: 15081990',
                    ),
                    (
                      'OnlineSBI download',
                      'Usually your account number (try without leading zeros too)',
                    ),
                    (
                      'Statement by SMS (ESTMT)',
                      'The 4-digit code you chose when you asked for it',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: T.s2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(where, style: T.label.copyWith(color: p.ink)),
                          Text(
                            rule,
                            style: T.bodySmall.copyWith(color: p.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    "SBI's covering email or SMS usually states the rule.",
                    style: T.bodySmall.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: T.s3),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Open'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows what was read and asks to import. Returns true on "Import".
Future<bool?> showStatementReviewSheet(
  BuildContext context,
  StatementPreview preview,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        SafeArea(top: false, child: _ReviewSheet(preview: preview)),
  );
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.preview});

  final StatementPreview preview;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final s = preview.statement;
    final salary = preview.analysis.salary;
    final allVerified = s.verifiedRows == s.rows.length;
    final debits = s.rows.fold<int>(0, (sum, r) => sum + r.debitPaise);
    final credits = s.rows.fold<int>(0, (sum, r) => sum + r.creditPaise);

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: T.body.copyWith(color: p.inkSecondary)),
          ),
          const SizedBox(width: T.s3),
          Flexible(
            child: Text(
              value,
              style: T.money.copyWith(color: p.ink),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Check before importing', style: T.title.copyWith(color: p.ink)),
          const SizedBox(height: T.s1),
          Text(
            '${s.bank} savings${s.accountMask == null ? '' : ' •• ${s.accountMask}'}'
            '${s.periodFrom == null ? '' : ' · ${_range(s.periodFrom, s.periodTo)}'}',
            style: T.bodySmall.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: T.s4),
          NoticeBanner(
            title: allVerified
                ? 'All ${s.rows.length} balances check out'
                : '${s.verifiedRows} of ${s.rows.length} balances check out',
            body: allVerified
                ? 'Every row was checked against the running balance the bank printed.'
                : "Some rows don't add up with the bank's running balance, usually a "
                      'page the PDF did not lay out cleanly. They are imported but marked.',
            icon: allVerified
                ? Icons.verified_rounded
                : Icons.error_outline_rounded,
            tone: allVerified ? PillTone.positive : PillTone.caution,
          ),
          const SizedBox(height: T.s3),
          line('Transactions', '${s.rows.length}'),
          line('Money out', money(Paise(debits))),
          line('Money in', money(Paise(credits))),
          if (s.openingBalancePaise != null)
            line('Opening balance', money(Paise(s.openingBalancePaise!))),
          if (s.closingBalancePaise != null)
            line('Closing balance', money(Paise(s.closingBalancePaise!))),
          const SizedBox(height: T.s3),
          Text(
            salary.found
                ? 'Salary found: ${money(Paise(salary.typicalPaise))}'
                      '${salary.payer == null ? '' : ' from ${salary.payer}'}. ${salary.reason}'
                : 'No salary found in this file. You can mark one after importing.',
            style: T.body.copyWith(color: p.inkSecondary),
          ),
          for (final w in s.warnings.where(
            (w) => !w.contains('did not reconcile'),
          )) ...[
            const SizedBox(height: T.s2),
            Text(w, style: T.bodySmall.copyWith(color: p.inkMuted)),
          ],
          const SizedBox(height: T.s5),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: T.s3),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Import'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
