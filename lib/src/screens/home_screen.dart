import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing, AppRadius;

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _filter = 'All';

  static const _filters = ['All', 'High Intent', 'New', 'Follow-up', 'Cold'];

  List<Lead> _applyFilter(List<Lead> all) => switch (_filter) {
    'High Intent' => all.where((l) => l.intent.toLowerCase().contains('high')).toList(),
    'New' => all.where((l) => l.score <= 0).toList(),
    'Follow-up' => all.where((l) => l.checklist.any((i) => !i.completed)).toList(),
    'Cold' => all.where((l) => l.score < 40 || l.intent.toLowerCase().contains('cold')).toList(),
    _ => all,
  };

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final filtered = _applyFilter(leads);

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildScrollBody(context, filtered)),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 19),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.westar)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Greeting + title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good morning, Ravi',
                  style: AppText.body13.copyWith(
                    color: AppColors.schooner,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Your Leads', style: AppText.display24),
              ],
            ),
          ),
          const SizedBox(width: 17),
          // Bell button with notification dot
          TapScale(
            onTap: () {},
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.pampas,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.westar),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.notifications_outlined,
                        size: 18,
                        color: AppColors.merlin,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.alizarin,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 17),
          // Add FAB
          TapScale(
            onTap: () => context.push('/outbound/add'),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.blueRibbon,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppShadows.blueAction,
              ),
              child: const Center(
                child: Icon(Icons.add, color: AppColors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Scrollable body ────────────────────────────────────────────────────────

  Widget _buildScrollBody(BuildContext context, List<Lead> leads) {
    return CustomScrollView(
      slivers: [
        // Stats row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: const [
                Expanded(
                  child: _StatTile(
                    icon: Icons.call_outlined,
                    label: 'Calls Today',
                    value: '24',
                    change: '+12%',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    icon: Icons.show_chart,
                    label: 'Avg Score',
                    value: '86',
                    valueColor: AppColors.blueRibbon,
                    suffix: '/100',
                  ),
                ),
              ],
            ),
          ),
        ),
        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _buildSearchBar(),
          ),
        ),
        // Filter chips
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildFilterChips(),
          ),
        ),
        // Lead list or empty state
        if (leads.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 40, color: AppColors.tide),
                  const SizedBox(height: 8),
                  Text(
                    _filter == 'All' ? 'No leads yet' : 'No $_filter leads',
                    style: AppText.body14.copyWith(
                      color: AppColors.schooner,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _filter == 'All'
                        ? 'Tap + to add your first lead'
                        : 'Try a different filter',
                    style: AppText.caption11,
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
            sliver: SliverList.separated(
              itemCount: leads.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _LeadTile(lead: leads[i]),
            ),
          ),
      ],
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.westar),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search, size: 16, color: AppColors.schooner),
                const SizedBox(width: 9),
                Text(
                  'Search leads...',
                  style: AppText.body14.copyWith(
                    color: AppColors.boulder,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // Filter button with blue active-dot
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.westar),
                ),
                child: const Center(
                  child: Icon(Icons.tune, size: 18, color: AppColors.merlin),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.blueRibbon,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final active = f == _filter;
          return TapScale(
            onTap: () => setState(() => _filter = f),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? AppColors.blueRibbon : AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: active ? null : Border.all(color: AppColors.westar),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.blueRibbon.withValues(alpha: 0.25),
                          offset: const Offset(0, 2),
                          blurRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  f,
                  style: AppText.body13.copyWith(
                    color: active ? AppColors.white : AppColors.merlin,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.065,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Stat tile ────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.zeus,
    this.suffix,
    this.change,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String? suffix;
  final String? change;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Icon(icon, size: 11, color: AppColors.schooner),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppText.label11,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Value row with optional change/suffix
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppText.mono(
                  size: 28,
                  weight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
              if (change != null) ...[
                const SizedBox(width: 6),
                Text(
                  change!,
                  style: AppText.body13.copyWith(
                    color: AppColors.salem,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  suffix!,
                  style: AppText.body13.copyWith(
                    color: AppColors.schooner,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Lead tile ────────────────────────────────────────────────────────────────

class _LeadTile extends ConsumerWidget {
  const _LeadTile({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TapScale(
      onTap: () {
        ref.read(selectedLeadIdProvider.notifier).set(lead.id);
        context.push('/leads/${lead.id}');
      },
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.westar),
          boxShadow: AppShadows.card,
        ),
        child: Stack(
          children: [
            // Subtle blue glow — top-right decoration
            Positioned(
              right: -20,
              top: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  color: Color(0x121E4AFF),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ScoreRing(score: lead.score, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          lead.name,
                          style: AppText.display16,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Phone
                        Row(
                          children: [
                            const Icon(
                              Icons.phone_outlined,
                              size: 11,
                              color: AppColors.schooner,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              lead.phone,
                              style: AppText.mono(
                                size: 12.5,
                                color: AppColors.schooner,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Intent + Source pills
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            if (lead.intent.isNotEmpty)
                              LpMiniPill(
                                label: lead.intent,
                                icon: Icons.bolt,
                                foreground: AppColors.greenHaze,
                                background: AppColors.foam,
                                border: AppColors.iceCold,
                              ),
                            LpMiniPill(
                              label: lead.source.displayName,
                              foreground: AppColors.governorBay,
                              background: AppColors.zircon,
                              border: AppColors.periwinkle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Timestamp · topic
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_outlined,
                              size: 11,
                              color: AppColors.tide,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _timeStamp(),
                                style: AppText.caption11.copyWith(
                                  color: AppColors.tide,
                                  fontSize: 11.5,
                                  height: 14 / 11.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Call button — taps go directly to caller selector
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/caller-selector/${lead.id}'),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.blueRibbon,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blueRibbon.withValues(alpha: 0.25),
                            offset: const Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.call, size: 16, color: AppColors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeStamp() {
    final diff = DateTime.now().difference(lead.lastContact);
    final String timeStr;
    if (diff.inMinutes < 60) {
      timeStr = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      timeStr = '$h hour${h == 1 ? '' : 's'} ago';
    } else if (diff.inDays == 1) {
      timeStr = '1 day ago';
    } else {
      timeStr = '${diff.inDays} days ago';
    }
    final topic = lead.propertyInterest;
    return (topic != null && topic.isNotEmpty) ? '$timeStr · $topic' : timeStr;
  }
}
