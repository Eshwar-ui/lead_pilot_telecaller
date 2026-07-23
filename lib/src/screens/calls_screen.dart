import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing, AppRadius;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import '../widgets/shimmer.dart';

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();
  String _query = '';

  /// 'All' | 'Inbound' | 'Outbound'.
  String _direction = 'All';

  static const _directions = ['All', 'Inbound', 'Outbound'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allCalls = ref.watch(callLogProvider);
    final loading = ref.watch(leadsLoadingProvider) && allCalls.isEmpty;
    final q = _query.trim().toLowerCase();
    var callLog = q.isEmpty
        ? allCalls
        : allCalls
            .where((e) =>
                e.leadName.toLowerCase().contains(q) ||
                e.phone.toLowerCase().contains(q))
            .toList();
    if (_direction != 'All') {
      final wantInbound = _direction == 'Inbound';
      callLog = callLog.where((e) => e.isInbound == wantInbound).toList();
    }
    final syncState = ref.watch(callLogSyncProvider);

    // Group by date section label
    final today = <CallLogEntry>[];
    final yesterday = <CallLogEntry>[];
    final older = <CallLogEntry>[];
    final n = DateTime.now();
    final now = DateTime(n.year, n.month, n.day);

    for (final entry in callLog) {
      final days = now
          .difference(DateTime(entry.calledAt.year, entry.calledAt.month, entry.calledAt.day))
          .inDays;
      if (days == 0) {
        today.add(entry);
      } else if (days == 1) {
        yesterday.add(entry);
      } else {
        older.add(entry);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            LpTabHeader(
              title: 'My Calls',
              subtitle: '${allCalls.length} call${allCalls.length == 1 ? '' : 's'} logged',
              actions: [
                _DirectionFilterButton(
                  active: _direction,
                  onTap: _openDirectionFilterSheet,
                ),
                LpIconButton(
                  icon: _searching ? Icons.close : Icons.search,
                  onTap: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _searchController.clear();
                      _query = '';
                    }
                  }),
                ),
              ],
            ),

            if (ref.watch(leadsUsingFallbackProvider))
              LpFallbackBanner(
                onRetry: () => ref.read(leadsProvider.notifier).refresh(),
              ),

            if (syncState.checked && !syncState.permissionGranted)
              _CallLogPermissionCard(
                onEnable: () =>
                    ref.read(callLogSyncProvider.notifier).requestPermissionAndSync(),
              ),

            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.westar),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 16, color: AppColors.schooner),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (v) => setState(() => _query = v),
                          style: AppText.body14.copyWith(color: AppColors.zeus),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Search calls...',
                            hintStyle: AppText.body14
                                .copyWith(color: AppColors.boulder),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: AppSpacing.sm),

            // ── Stats (computed from real data) ───────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Builder(builder: (_) {
                final now = DateTime.now();
                final thisMonth = callLog.where((e) =>
                    e.calledAt.year == now.year &&
                    e.calledAt.month == now.month).toList();
                final avgScore = callLog.isEmpty
                    ? 0
                    : (callLog.map((e) => e.score).fold(0, (a, b) => a + b) ~/
                        callLog.length);
                final totalSecs = callLog.fold(0, (a, e) => a + e.duration.inSeconds);
                final avgSecs = callLog.isEmpty ? 0 : totalSecs ~/ callLog.length;
                final avgDur =
                    '${(avgSecs ~/ 60).toString().padLeft(2, '0')}:${(avgSecs % 60).toString().padLeft(2, '0')}';
                return Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'This Month',
                        value: '${thisMonth.length}',
                        mono: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: MetricTile(
                        label: 'Avg Score',
                        value: callLog.isEmpty ? '—' : '$avgScore',
                        valueColor: AppColors.salem,
                        mono: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: MetricTile(
                        label: 'Avg Duration',
                        value: callLog.isEmpty ? '—' : avgDur,
                        mono: true,
                      ),
                    ),
                  ],
                );
              }),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Call list ─────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                children: [
                  if (loading) ...[
                    for (var i = 0; i < 5; i++) const _CallTileSkeleton(),
                  ] else if (callLog.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          const Icon(Icons.call_outlined,
                              size: 40, color: AppColors.tide),
                          const SizedBox(height: 8),
                          Text(
                            q.isEmpty ? 'No calls yet' : 'No matching calls',
                            style: AppText.body14.copyWith(
                              color: AppColors.schooner,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            q.isEmpty
                                ? 'Calls you make will show up here'
                                : 'Try a different search',
                            style: AppText.caption11,
                          ),
                        ],
                      ),
                    ),
                  if (today.isNotEmpty) ...[
                    _SectionLabel(label: 'TODAY'),
                    for (final e in today) _CallTile(entry: e),
                  ],
                  if (yesterday.isNotEmpty) ...[
                    _SectionLabel(label: 'YESTERDAY'),
                    for (final e in yesterday) _CallTile(entry: e),
                  ],
                  if (older.isNotEmpty) ...[
                    _SectionLabel(label: 'EARLIER'),
                    for (final e in older) _CallTile(entry: e),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDirectionFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.westar,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Filter by direction', style: AppText.display20.copyWith(fontSize: 18)),
              const SizedBox(height: AppSpacing.md),
              for (final d in _directions)
                TapScale(
                  onTap: () {
                    setState(() => _direction = d);
                    Navigator.of(sheetContext).pop();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: d == _direction ? AppColors.ribbonSurface : AppColors.pampas,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: d == _direction ? AppColors.blueRibbon : AppColors.westar,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            d,
                            style: AppText.body14.copyWith(
                              fontWeight: FontWeight.w600,
                              color: d == _direction ? AppColors.blueRibbon : AppColors.zeus,
                            ),
                          ),
                        ),
                        if (d == _direction)
                          const Icon(Icons.check, size: 18, color: AppColors.blueRibbon),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionFilterButton extends StatelessWidget {
  const _DirectionFilterButton({required this.active, required this.onTap});

  final String active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filterActive = active != 'All';
    return TapScale(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: filterActive ? AppColors.blueRibbon : AppColors.pampas,
                shape: BoxShape.circle,
                border: Border.all(
                  color: filterActive ? AppColors.blueRibbon : AppColors.westar,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.tune,
                  size: 18,
                  color: filterActive ? AppColors.white : AppColors.merlin,
                ),
              ),
            ),
            if (filterActive)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.alizarin,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Prompts the telecaller to grant call-log access so this screen can show
/// every real call (inbound/outbound/missed), not just calls placed through
/// the app's own Call button. Shown only after the initial permission check
/// completes and comes back denied — never blocks the (already-working)
/// app-placed-call list underneath it.
class _CallLogPermissionCard extends StatelessWidget {
  const _CallLogPermissionCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.zircon,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.periwinkle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.call_outlined, size: 18, color: AppColors.governorBay),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'See every call, not just calls made from this app',
                  style: AppText.body14.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.governorBay,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Grant call log access to log inbound, outbound and missed calls automatically.",
                  style: AppText.caption11.copyWith(color: AppColors.governorBay),
                ),
                const SizedBox(height: AppSpacing.sm),
                TapScale(
                  onTap: onEnable,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.blueRibbon,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      'Enable',
                      style: AppText.body13.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(label, style: AppText.label11),
    );
  }
}

class _CallTileSkeleton extends StatelessWidget {
  const _CallTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.westar),
      ),
      child: Row(
        children: [
          const ShimmerBox(width: 36, height: 36, borderRadius: 8),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: double.infinity, height: 14),
                SizedBox(height: 6),
                ShimmerBox(width: 100, height: 11),
                SizedBox(height: 8),
                ShimmerBox(width: 120, height: 16, borderRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          const ShimmerBox(width: 38, height: 38, borderRadius: 19),
        ],
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.entry});

  final CallLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final dur = _fmtDuration(entry.duration);
    final time = _fmtWhen(entry.calledAt);

    return GestureDetector(
      onTap: entry.leadId != null
          ? () => context.push('/leads/${entry.leadId}')
          : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Direction indicator
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.isInbound ? AppColors.violetSurface : AppColors.foam,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              entry.isInbound ? Icons.call_received_outlined : Icons.call_made_outlined,
              size: 16,
              color: entry.isInbound ? AppColors.electricViolet : AppColors.greenHaze,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.leadName,
                        style: AppText.body14.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(time, style: AppText.caption11),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(entry.phone, style: AppText.mono(size: 11)),
                    const Spacer(),
                    Text(dur, style: AppText.mono(size: 11, color: AppColors.schooner)),
                  ],
                ),
                // Source/intent pills only mean something once this call is
                // tied to a known lead — a bare device call-log entry (e.g. a
                // personal call, or a number not in the CRM yet) has neither,
                // and showing an empty or placeholder pill for it would read
                // as a fabricated lead-source claim.
                if (entry.leadId != null &&
                    (entry.source.displayName.isNotEmpty || entry.intent.isNotEmpty)) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      LpMiniPill(
                        label: entry.source.displayName,
                        foreground: AppColors.governorBay,
                        background: AppColors.zircon,
                        border: AppColors.periwinkle,
                      ),
                      if (entry.intent.isNotEmpty)
                        LpMiniPill(
                          label: entry.intent,
                          foreground: AppColors.greenHaze,
                          background: AppColors.foam,
                          border: AppColors.iceCold,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // A score ring only makes sense for a call that was actually
          // recorded and AI-analyzed (has a backend call_id) — a plain
          // device call-log entry has no score, and ScoreRing's own
          // score<=0 fallback reads as "New", which is misleading here.
          if (entry.callId != null) ...[
            const SizedBox(width: AppSpacing.xs),
            ScoreRing(score: entry.score, size: 38),
          ],
        ],
      ),
    ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// The tile's trailing timestamp. A bare time is only unambiguous for
  /// today's calls — for anything older, show the date too (with the year
  /// once it's a previous year) so "3:40 PM" on a two-week-old call isn't
  /// mistaken for today.
  String _fmtWhen(DateTime at) {
    final now = DateTime.now();
    final callDay = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diffDays = today.difference(callDay).inDays;
    if (diffDays == 0) return DateFormat('h:mm a').format(at);
    if (diffDays == 1) return 'Yesterday, ${DateFormat('h:mm a').format(at)}';
    if (at.year == now.year) return DateFormat('d MMM, h:mm a').format(at);
    return DateFormat('d MMM yyyy, h:mm a').format(at);
  }
}
