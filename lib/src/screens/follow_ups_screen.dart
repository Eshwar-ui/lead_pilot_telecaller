import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing, AppRadius;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import '../widgets/schedule_call_sheet.dart';
import '../widgets/shimmer.dart';

class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Pull-to-refresh handler — re-pulls follow-ups (incl. any created/synced
  /// on another device under the same telecaller account).
  Future<void> _refresh() =>
      ref.read(followUpsProvider.notifier).refresh();

  /// Pick a lead, then open the schedule sheet to create a follow-up reminder.
  Future<void> _addFollowUp() async {
    final leads = ref.read(leadsProvider);
    if (leads.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Add a lead first to schedule a follow-up.')),
        );
      return;
    }
    final lead = await showModalBottomSheet<Lead>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.fromLTRB(0, 14, 0, 12),
                decoration: BoxDecoration(
                  color: AppColors.westar,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Choose a lead',
                  style: AppText.display20.copyWith(fontSize: 18)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: leads.length,
                itemBuilder: (_, i) {
                  final l = leads[i];
                  return ListTile(
                    leading: ScoreRing(score: l.score, size: 38),
                    title: Text(l.name,
                        style:
                            AppText.body14.copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text(l.phone, style: AppText.mono(size: 12)),
                    onTap: () => Navigator.of(sheetContext).pop(l),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (lead != null && mounted) {
      await ScheduleCallSheet.show(context, lead);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(followUpsProvider);
    final loading = ref.watch(followUpsLoadingProvider) && tasks.isEmpty;

    final overdue = tasks.where((t) => t.status == FollowUpStatus.overdue).toList();
    final pending = tasks.where((t) => t.status == FollowUpStatus.pending).toList();
    final done = tasks.where((t) => t.status == FollowUpStatus.done).toList();

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            LpTabHeader(
              title: 'Follow-ups',
              subtitleWidget: RichText(
                text: TextSpan(
                  style: AppText.body13.copyWith(color: AppColors.schooner),
                  children: [
                    TextSpan(
                      text: '${overdue.length} overdue',
                      style: TextStyle(
                        color: overdue.isNotEmpty
                            ? AppColors.alizarin
                            : AppColors.schooner,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: ' · ${pending.length} due today'),
                  ],
                ),
              ),
              actions: [
                LpIconButton(icon: Icons.add, onTap: _addFollowUp),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Stats row ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Overdue',
                      value: '${overdue.length}',
                      valueColor: AppColors.alizarin,
                      mono: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MetricTile(
                      label: 'Due Today',
                      value: '${pending.length}',
                      valueColor: AppColors.tahitiGold,
                      mono: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MetricTile(
                      label: 'Done',
                      value: '${done.length}',
                      valueColor: AppColors.salem,
                      mono: true,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Filter tabs ────────────────────────────────────────────────
            Container(
              color: AppColors.white,
              child: TabBar(
                controller: _tabs,
                labelColor: AppColors.blueRibbon,
                unselectedLabelColor: AppColors.schooner,
                indicatorColor: AppColors.blueRibbon,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: AppText.body13.copyWith(fontWeight: FontWeight.w700),
                unselectedLabelStyle: AppText.body13,
                dividerColor: AppColors.westar,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Today'),
                  Tab(text: 'Upcoming'),
                ],
              ),
            ),

            // ── Task lists ─────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _TaskList(
                    tasks: tasks,
                    loading: loading,
                    onRefresh: _refresh,
                  ),
                  _TaskList(
                    tasks: tasks.where((t) => t.dueToday).toList(),
                    loading: loading,
                    onRefresh: _refresh,
                    emptyTitle: 'Nothing due today',
                    emptySubtitle: 'Check Upcoming for future tasks',
                  ),
                  _TaskList(
                    tasks: tasks
                        .where(
                          (t) =>
                              t.status == FollowUpStatus.pending && !t.dueToday,
                        )
                        .toList(),
                    loading: loading,
                    onRefresh: _refresh,
                    emptyTitle: 'No upcoming tasks',
                    emptySubtitle: 'You\'re on top of everything',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    this.loading = false,
    this.onRefresh,
    this.emptyTitle = 'All caught up!',
    this.emptySubtitle = 'No tasks here',
  });

  final List<FollowUpTask> tasks;
  final bool loading;
  final Future<void> Function()? onRefresh;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: const [
          _TaskTileSkeleton(),
          _TaskTileSkeleton(),
          _TaskTileSkeleton(),
          _TaskTileSkeleton(),
        ],
      );
    }

    final Widget list;
    if (tasks.isEmpty) {
      // Keep the empty state scrollable so pull-to-refresh still works when
      // there are no tasks yet (e.g. before another device's follow-ups sync).
      list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 120),
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 40, color: AppColors.tide),
              const SizedBox(height: 8),
              Text(
                emptyTitle,
                style: AppText.body14.copyWith(
                  color: AppColors.schooner,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(emptySubtitle, style: AppText.caption11),
            ],
          ),
        ],
      );
    } else {
      // Separate overdue from the rest for ordering
      final overdue = tasks.where((t) => t.status == FollowUpStatus.overdue).toList();
      final rest = tasks.where((t) => t.status != FollowUpStatus.overdue).toList();

      list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (overdue.isNotEmpty) ...[
            _SectionLabel('OVERDUE', color: AppColors.alizarin),
            for (final t in overdue) _TaskTile(task: t),
          ],
          if (rest.isNotEmpty) ...[
            _SectionLabel('TODAY'),
            for (final t in rest) _TaskTile(task: t),
          ],
        ],
      );
    }

    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.color = AppColors.schooner});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(label, style: AppText.label11.copyWith(color: color)),
    );
  }
}

class _TaskTileSkeleton extends StatelessWidget {
  const _TaskTileSkeleton();

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
          const ShimmerBox(width: 22, height: 22, borderRadius: 11),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: double.infinity, height: 14),
                SizedBox(height: 6),
                ShimmerBox(width: 110, height: 12),
                SizedBox(height: 6),
                ShimmerBox(width: 80, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final FollowUpTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOverdue = task.status == FollowUpStatus.overdue;
    final isDone = task.status == FollowUpStatus.done;
    final notifier = ref.read(followUpsProvider.notifier);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.alizarin,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => notifier.delete(task.id),
      child: TapScale(
      onTap: task.leadId != null
          ? () => context.push('/leads/${task.leadId}')
          : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: isOverdue ? AppColors.redSurface : AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isOverdue ? AppColors.redBorder : AppColors.westar,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Checkbox circle — tap to mark done
          GestureDetector(
            onTap: isDone ? null : () => notifier.markDone(task.id),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.salem : Colors.transparent,
                border: Border.all(
                  color: isDone
                      ? AppColors.salem
                      : isOverdue
                          ? AppColors.alizarin
                          : AppColors.westar,
                  width: 1.5,
                ),
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 12, color: AppColors.white)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.taskText,
                        style: AppText.body14.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                          color: isDone ? AppColors.schooner : AppColors.zeus,
                        ),
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOverdue ? AppColors.alizarin : AppColors.pampas,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        isOverdue ? 'OVERDUE' : 'PENDING',
                        style: AppText.label11.copyWith(
                          color: isOverdue ? AppColors.white : AppColors.schooner,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      task.leadName,
                      style: AppText.body13.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (task.phone != null) ...[
                      const SizedBox(width: 6),
                      Text(task.phone!, style: AppText.mono(size: 11)),
                    ],
                  ],
                ),
                if (task.dueLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    task.dueLabel!,
                    style: AppText.caption11.copyWith(
                      color: isOverdue ? AppColors.alizarin : AppColors.schooner,
                      fontWeight: isOverdue ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    ),
    );
  }
}
