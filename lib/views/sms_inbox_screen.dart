import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../domain/enums.dart';
import '../domain/sms_inbox.dart';
import '../domain/sms_message.dart';
import '../domain/transaction.dart';
import '../services/sms/sender_registry.dart';
import '../services/sms/transaction_extractor.dart';
import '../state/app_state.dart';
import 'widgets/inbox_common.dart';
import 'widgets/inbox_detail_sheet.dart';
import 'widgets/inbox_filter_bar.dart';
import 'widgets/inbox_funnel_header.dart';
import 'widgets/inbox_message_tile.dart';

/// The optional "All messages" review screen.
///
/// Nothing in the app depends on it: it is a pushed route with its own Skip,
/// it never shows a launch modal or an undismissable badge, and every action is
/// scoped — the owner chooses "just this payment" or "every payment from X".
///
/// Wire it from anywhere with `SmsInboxScreen.open` (or `openSmsInbox` from
/// `app.dart`); the route name is [routeName] (`messages`).
class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({
    super.key,
    this.initialFilter = InboxFilter.all,
  });

  /// Which slice the caller wants to land on. Home's "12 to confirm" opens the
  /// review filter, so the user does not start on 2,000 unfiltered rows.
  final InboxFilter initialFilter;

  /// `messages` — the name other screens can push without importing this file.
  static const String routeName = 'messages';

  static Route<void> route({InboxFilter initialFilter = InboxFilter.all}) =>
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => SmsInboxScreen(initialFilter: initialFilter),
      );

  static Future<void> open(
    BuildContext context, {
    InboxFilter initialFilter = InboxFilter.all,
  }) => Navigator.of(context).push(route(initialFilter: initialFilter));

  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> {
  static const int _pageSize = 50;
  static const SenderRegistry _registry = SenderRegistry();
  static final TransactionExtractor _extractor = TransactionExtractor();

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final Map<String, Txn?> _parsedCache = <String, Txn?>{};

  Timer? _debounce;
  late InboxFilter _filter = widget.initialFilter;
  final List<SmsMessageRow> _rows = <SmsMessageRow>[];
  InboxStats _stats = InboxStats.empty;
  Set<String> _excludedShapes = const <String>{};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _generation = 0;

  String get _query => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 420) _loadMore();
  }

  Future<void> _reload() async {
    final store = context.read<AppState>().inboxStore;
    final generation = ++_generation;
    if (store == null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _error = null;
        _rows.clear();
        _stats = InboxStats.empty;
        _excludedShapes = const <String>{};
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final rows = await store.recentMessages(
        offset: 0,
        limit: _pageSize,
        filter: _filter.slug,
        query: _query.isEmpty ? null : _query,
      );
      final stats = await store.inboxStats();
      final shapes = await store.excludedShapes();
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _stats = stats;
        _excludedShapes = shapes;
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'The messages could not be read just now. Pull down to try '
            'again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final store = context.read<AppState>().inboxStore;
    if (store == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final rows = await store.recentMessages(
        offset: _rows.length,
        limit: _pageSize,
        filter: _filter.slug,
        query: _query.isEmpty ? null : _query,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows.addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await context.read<AppState>().refresh();
    if (!mounted) return;
    await _reload();
  }

  void _onFilter(InboxFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _debounce?.cancel();
    _reload();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _reload();
    });
  }

  Txn? _parse(SmsMessageRow row) {
    if (_parsedCache.containsKey(row.id)) return _parsedCache[row.id];
    final message = SmsMessage(
      id: row.id,
      sender: row.sender,
      body: row.body,
      receivedAtMs: row.receivedAtMs,
    );
    final parsed = _extractor.extract(message, _registry.resolve(row.sender));
    _parsedCache[row.id] = parsed;
    return parsed;
  }

  InboxRowStatus _status(SmsMessageRow row, Txn? parsed, Txn? stored) {
    if (row.smsClass == SmsClass.phishing) return InboxRowStatus.flagged;
    if (isExcludedShape(parsed ?? stored, _excludedShapes)) {
      return InboxRowStatus.notCounted;
    }
    // A ledger row is the strongest evidence that this message is a payment —
    // it also covers a payment the owner typed in by hand, whose stored class
    // may still be informational.
    if (stored != null) return InboxRowStatus.transaction;
    return inboxRowStatus(row, hasTransaction: parsed != null);
  }

  Future<void> _openMessage(SmsMessageRow row) async {
    final store = context.read<AppState>().inboxStore;
    if (store == null) return;
    final parsed = _parse(row);
    final stored = _storedTransactions()[messageTxnKey(row)];
    final status = _status(row, parsed, stored);
    final outcome = await showInboxMessageSheet(
      context,
      row: row,
      store: store,
      status: status,
      parsed: parsed,
      stored: stored,
    );
    if (!mounted || outcome == null) return;
    await context.read<AppState>().refresh();
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(outcome.message)),
    );
  }

  Map<String, Txn> _storedTransactions() {
    final transactions = context.read<AppState>().data.transactions;
    return {for (final txn in transactions) txn.key: txn};
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = state.inboxStore;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: T.s5,
        title: const Text('All messages'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Skip'),
          ),
          const SizedBox(width: T.s1),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: store == null
            ? _NoInbox(state: state, onSkip: () => Navigator.of(context).maybePop())
            : RefreshIndicator(onRefresh: _refresh, child: _buildList(state)),
      ),
    );
  }

  Widget _buildList(AppState state) {
    final now = DateTime.now();
    final stored = _storedTransactions();

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InboxFunnelHeader(stats: _stats, isDemo: state.isDemo),
                const SizedBox(height: T.s4),
                InboxFilterBar(
                  controller: _search,
                  filter: _filter,
                  onFilter: _onFilter,
                  onQueryChanged: _onQueryChanged,
                ),
                const SizedBox(height: T.s3),
              ],
            ),
          ),
        ),
        if (_error != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s3),
            sliver: SliverToBoxAdapter(
              child: NoticeBanner(
                title: 'Could not read the inbox',
                body: _error!,
                tone: PillTone.danger,
                icon: Icons.error_outline_rounded,
                actionLabel: 'Try again',
                onAction: _reload,
              ),
            ),
          ),
        if (_loading && _rows.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
            sliver: SliverToBoxAdapter(child: _InboxSkeleton()),
          )
        else if (_rows.isEmpty)
          SliverToBoxAdapter(child: _emptyState(state))
        else
          SliverList.builder(
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final parsed = _parse(row);
              final storedTxn = stored[messageTxnKey(row)];
              return Padding(
                padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s2),
                child: InboxMessageTile(
                  row: row,
                  parsed: parsed,
                  stored: storedTxn,
                  status: _status(row, parsed, storedTxn),
                  now: now,
                  onTap: () => _openMessage(row),
                ),
              );
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, T.s8),
            child: _Footer(
              hasMore: _hasMore,
              loadingMore: _loadingMore,
              onLoadMore: _loadMore,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(AppState state) {
    final filtered = _filter != InboxFilter.all || _query.isNotEmpty;
    if (_stats.total == 0 && !filtered) {
      return Padding(
        padding: const EdgeInsets.only(top: T.s6),
        child: EmptyState(
          icon: Icons.mark_email_unread_outlined,
          title: 'No messages yet',
          body:
              'The app reads bank and UPI texts on this phone automatically as '
              'they arrive. When the first one lands it shows up here, newest '
              'first — nothing needs setting up.',
          actionLabel: state.isDemo ? 'Exit demo' : 'Scan SMS now',
          onAction: state.isDemo ? state.exitDemo : state.scanInbox,
          secondaryLabel: 'Skip for now',
          onSecondary: () => Navigator.of(context).maybePop(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: T.s6),
      child: EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing matches',
        body: 'No message fits this filter and search. Clear them to see the '
            'whole inbox again.',
        actionLabel: 'Clear filters',
        onAction: () {
          _search.clear();
          setState(() => _filter = InboxFilter.all);
          _reload();
        },
        secondaryLabel: 'Skip for now',
        onSecondary: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (hasMore)
          TextButton(
            onPressed: loadingMore ? null : onLoadMore,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: loadingMore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Load more'),
          ),
        const InboxPrivacyFooter(),
      ],
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SkeletonBox(height: 188, radius: T.r3),
        const SizedBox(height: T.s4),
        const SkeletonBox(height: 48, radius: T.r2),
        const SizedBox(height: T.s3),
        for (var i = 0; i < 5; i++) ...[
          const SkeletonBox(height: 112, radius: T.r3),
          const SizedBox(height: T.s2),
        ],
      ],
    );
  }
}

class _NoInbox extends StatelessWidget {
  const _NoInbox({required this.state, required this.onSkip});

  final AppState state;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, T.s6),
      children: [
        InboxFunnelHeader(stats: InboxStats.empty, isDemo: state.isDemo),
        const SizedBox(height: T.s4),
        EmptyState(
          icon: Icons.sms_outlined,
          title: state.isDemo ? 'Demo mode shows no texts' : 'Messages stay on this phone',
          body: state.isDemo
              ? 'Demo data is generated, so there are no sample SMS to list. '
                    'On your phone, every bank and UPI alert appears here, '
                    'newest first.'
              : 'Allow SMS access on Android and every stored bank or UPI '
                    'message is listed here. Nothing is uploaded.',
          actionLabel: state.isDemo ? 'Exit demo' : 'Allow SMS access',
          onAction: state.isDemo ? state.exitDemo : state.scanInbox,
          secondaryLabel: 'Skip for now',
          onSecondary: onSkip,
        ),
        const InboxPrivacyFooter(),
      ],
    );
  }
}
