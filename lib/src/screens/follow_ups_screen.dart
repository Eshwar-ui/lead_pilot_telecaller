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

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(followUpsProvider);

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Follow-ups',
                          style: AppText.display20.copyWith(fontSize: 22),
                        ),
                        RichText(
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
                      ],
                    ),
                  ),
                  LpIconButton(icon: Icons.add, onTap: () {}),
                ],
              ),
            ),

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
                  _TaskList(tasks: tasks),
                  _TaskList(
                    tasks: tasks.where((t) => t.dueToday).toList(),
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
    this.emptyTitle = 'All caught up!',
    this.emptySubtitle = 'No tasks here',
  });

  final List<FollowUpTask> tasks;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
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
      );
    }

    // Separate overdue from the rest for ordering
    final overdue = tasks.where((t) => t.status == FollowUpStatus.overdue).toList();
    final rest = tasks.where((t) => t.status != FollowUpStatus.overdue).toList();

    return ListView(
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

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final FollowUpTask task;

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.status == FollowUpStatus.overdue;
    final isDone = task.status == FollowUpStatus.done;

    return TapScale(
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
          // Checkbox circle
          Container(
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
    );
  }
}
