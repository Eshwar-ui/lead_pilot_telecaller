import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/api/api_exception.dart';
import '../core/api/http_api_client.dart';
import '../data/attendance_repository.dart';
import '../data/lead_repository.dart';
import '../data/mock_leads.dart';
import '../models/attendance_record.dart';
import '../models/lead.dart';
import '../services/local_call_store.dart';
import '../services/local_follow_up_store.dart';
import '../services/local_lead_override_store.dart';
import '../services/session_store.dart';

// ─── Backend wiring ───────────────────────────────────────────────────────────

/// The HTTP transport. Swap the implementation here (or override in tests)
/// without touching call sites. Reads the session's JWT fresh on every
/// request so login/logout take effect immediately.
final apiClientProvider = Provider<ApiClient>(
  (ref) => HttpApiClient(getToken: () => ref.read(sessionProvider).token),
);

/// Maps the FastAPI "AI layer" responses into the app's domain models.
final leadRepositoryProvider = Provider<LeadRepository>(
  (ref) => LeadRepository(ref.watch(apiClientProvider)),
);

/// Talks to the attendance (clock in/out) endpoints.
final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(apiClientProvider)),
);

// ─── Leads (inbox) ────────────────────────────────────────────────────────────

/// Holds the inbox lead list. With [ApiConfig.useMockData] off, it hydrates
/// from `GET /api/inbox` and falls back to mock data if the backend is
/// unreachable — so the UI keeps the synchronous `List<Lead>` contract and no
/// screen needs to change.
final leadsProvider = NotifierProvider<LeadsController, List<Lead>>(
  LeadsController.new,
);

/// True when [leadsProvider] is showing mock/cached data because the last
/// backend fetch failed — screens watch this to show [LpFallbackBanner]
/// instead of silently letting mock leads look like a live inbox.
final leadsUsingFallbackProvider =
    NotifierProvider<LeadsUsingFallbackController, bool>(
      LeadsUsingFallbackController.new,
    );

class LeadsUsingFallbackController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class LeadsController extends Notifier<List<Lead>> {
  /// Locally-saved manual edits, applied on top of whatever the backend/mock
  /// returns so edits persist across restarts and show everywhere.
  Map<String, LeadOverride> _overrides = const {};

  @override
  List<Lead> build() {
    if (ApiConfig.useMockData) {
      _loadOverrides();
      return mockLeads;
    }
    // Kick off the async load; start empty so no stale mock data flashes.
    _load();
    return const [];
  }

  Future<void> _loadOverrides() async {
    _overrides = await ref.read(localLeadOverrideStoreProvider).loadAll();
    if (_overrides.isNotEmpty) state = [for (final l in state) _withOverride(l)];
  }

  Lead _withOverride(Lead lead) =>
      _overrides[lead.id]?.applyTo(lead) ?? lead;

  Future<void> _load() async {
    _overrides = await ref.read(localLeadOverrideStoreProvider).loadAll();
    try {
      final fetched = await ref.read(leadRepositoryProvider).fetchInbox();
      state = [for (final l in fetched) _withOverride(l)];
      ref.read(leadsUsingFallbackProvider.notifier).set(false);
    } catch (_) {
      // Backend unreachable — keep the app usable on mock data, but flag it
      // so the UI can tell the telecaller these aren't live leads.
      state = [for (final l in mockLeads) _withOverride(l)];
      ref.read(leadsUsingFallbackProvider.notifier).set(true);
    }
  }

  /// Re-fetch the inbox (e.g. pull-to-refresh, or after an upload completes).
  Future<void> refresh() => _load();

  /// Replace a thin inbox card with the fully-enriched lead detail
  /// (memory bubble, call history, objections, script). Called when a lead is
  /// opened. Silently no-ops on failure, leaving the thin card in place.
  Future<void> enrich(String contactKey) async {
    if (ApiConfig.useMockData || contactKey.isEmpty) return;
    try {
      final detailed =
          await ref.read(leadRepositoryProvider).leadDetail(contactKey);
      state = [
        for (final lead in state)
          if (lead.id == contactKey) _withOverride(detailed) else lead,
      ];
    } catch (_) {/* keep the thin card */}
  }

  /// Persist a manual edit to a lead and reflect it immediately everywhere.
  Future<void> updateLead(String leadId, LeadOverride override) async {
    await ref.read(localLeadOverrideStoreProvider).put(leadId, override);
    _overrides = {..._overrides, leadId: override};
    state = [
      for (final lead in state)
        if (lead.id == leadId) override.applyTo(lead) else lead,
    ];
  }
}

// Follow-ups: locally persisted via SharedPreferences.
// Backend endpoint doesn't exist yet; wire it here when it does.
final followUpsProvider =
    NotifierProvider<FollowUpController, List<FollowUpTask>>(
  FollowUpController.new,
);

class FollowUpController extends Notifier<List<FollowUpTask>> {
  @override
  List<FollowUpTask> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    state = await ref.read(localFollowUpStoreProvider).loadAll();
  }

  Future<void> schedule(FollowUpTask task) async {
    await ref.read(localFollowUpStoreProvider).add(task);
    unawaited(_load());
  }

  Future<void> markDone(String id) async {
    await ref.read(localFollowUpStoreProvider).markDone(id);
    unawaited(_load());
  }

  Future<void> delete(String id) async {
    await ref.read(localFollowUpStoreProvider).delete(id);
    unawaited(_load());
  }
}

/// Global call log: merges every enriched lead's backend history with calls
/// placed from inside the app (persisted locally), de-duplicated and sorted
/// newest-first. Entries appear immediately when a call is started, and again
/// as leads are enriched or a call is transcribed.
final callLogProvider = Provider<List<CallLogEntry>>((ref) {
  final leads = ref.watch(leadsProvider);
  final localCalls = ref.watch(localCallsProvider);
  final entries = <CallLogEntry>[];

  for (final lead in leads) {
    for (final call in lead.history) {
      entries.add(CallLogEntry(
        id: '${lead.id}_${call.calledAt?.millisecondsSinceEpoch ?? call.title.hashCode}',
        leadName: lead.name,
        phone: lead.phone,
        intent: lead.intent,
        source: lead.source,
        duration: call.duration,
        score: call.score,
        calledAt: call.calledAt ?? DateTime.now(),
        leadId: lead.id,
      ));
    }
  }

  // Add locally-recorded calls that the backend history doesn't already cover
  // (same lead + same minute is treated as the same call).
  bool covered(CallLogEntry local) => entries.any((e) =>
      e.leadId == local.leadId &&
      e.calledAt.difference(local.calledAt).inMinutes.abs() < 1);
  for (final local in localCalls) {
    if (!covered(local)) entries.add(local);
  }

  entries.sort((a, b) => b.calledAt.compareTo(a.calledAt));
  return entries;
});

/// Records a call placed from inside the app so it shows up in the call log
/// and the lead's history right away. Call after a successful dial launch.
Future<void> recordOutboundCall(WidgetRef ref, Lead lead) async {
  final now = DateTime.now();
  await ref.read(localCallsProvider.notifier).record(
        CallLogEntry(
          id: '${lead.id}_${now.millisecondsSinceEpoch}',
          leadName: lead.name,
          phone: lead.phone,
          intent: lead.intent,
          source: lead.source,
          duration: Duration.zero,
          score: lead.score,
          calledAt: now,
          leadId: lead.id,
        ),
      );
}

// ─── Checklist extras ─────────────────────────────────────────────────────────

/// Real-estate standard pre-call checklist items — shown when the backend
/// returns no checklist for a lead (currently always the case).
const defaultChecklistItems = [
  ChecklistItem(id: '__budget', text: 'Confirm budget range', completed: false),
  ChecklistItem(id: '__type', text: 'Property type (1BHK / 2BHK / 3BHK)', completed: false),
  ChecklistItem(id: '__location', text: 'Preferred location / project', completed: false),
  ChecklistItem(id: '__timeline', text: 'Move-in timeline', completed: false),
  ChecklistItem(id: '__loan', text: 'Loan / financing pre-approval', completed: false),
];

/// Per-lead extra checklist items added by the telecaller via "Add item…".
final checklistExtrasProvider =
    NotifierProvider<ChecklistExtrasController, Map<String, List<ChecklistItem>>>(
  ChecklistExtrasController.new,
);

class ChecklistExtrasController
    extends Notifier<Map<String, List<ChecklistItem>>> {
  @override
  Map<String, List<ChecklistItem>> build() => {};

  void addItem(String leadId, String text) {
    final current = {...state};
    final items = List<ChecklistItem>.from(current[leadId] ?? []);
    items.add(
      ChecklistItem(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        text: text,
        completed: false,
      ),
    );
    current[leadId] = items;
    state = current;
  }
}

/// Telecaller rolling score + trend (Profile / Score tab).
final telecallerScoreProvider = FutureProvider<TelecallerScore>((ref) async {
  if (ApiConfig.useMockData) {
    return const TelecallerScore(
      score: 84,
      trend: 2,
      trendDirection: 'up',
      calls: 23,
      avgLeadScore: 58,
      hotLeads: 4,
      windowDays: 7,
    );
  }
  return ref.read(leadRepositoryProvider).telecallerScore();
});

final callNotesProvider =
    NotifierProvider<CallNotesController, Map<String, String>>(
      CallNotesController.new,
    );

class CallNotesController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => {};

  void setNotes(String leadId, String notes) {
    state = {...state, leadId: notes};
  }
}

final selectedLeadIdProvider =
    NotifierProvider<SelectedLeadIdController, String>(
      SelectedLeadIdController.new,
    );

class SelectedLeadIdController extends Notifier<String> {
  @override
  String build() => ApiConfig.useMockData ? mockLeads.first.id : '';

  void set(String value) {
    state = value;
    // Lazily enrich the opened lead with detail (memory bubble, history, …).
    ref.read(leadsProvider.notifier).enrich(value);
  }
}

final selectedLeadProvider = Provider<Lead>((ref) {
  final leads = ref.watch(leadsProvider);
  final id = ref.watch(selectedLeadIdProvider);
  if (leads.isEmpty) return Lead.empty();
  return leads.firstWhere((lead) => lead.id == id, orElse: () => leads.first);
});

final checklistProvider =
    NotifierProvider<ChecklistController, Map<String, Set<String>>>(
      ChecklistController.new,
    );

class ChecklistController extends Notifier<Map<String, Set<String>>> {
  @override
  Map<String, Set<String>> build() {
    return {
      for (final lead in mockLeads)
        lead.id: lead.checklist
            .where((item) => item.completed)
            .map((item) => item.id)
            .toSet(),
    };
  }

  void toggle(String leadId, String itemId) {
    final current = {...state};
    final selected = {...(current[leadId] ?? <String>{})};
    selected.contains(itemId) ? selected.remove(itemId) : selected.add(itemId);
    current[leadId] = selected;
    state = current;
  }
}

enum CallerChoice { phone, trueCaller, others }

final callerChoiceProvider =
    NotifierProvider<CallerChoiceController, CallerChoice?>(
      CallerChoiceController.new,
    );
final rememberCallerChoiceProvider =
    NotifierProvider<RememberCallerChoiceController, bool>(
      RememberCallerChoiceController.new,
    );

class CallerChoiceController extends Notifier<CallerChoice?> {
  @override
  CallerChoice? build() => null;

  void set(CallerChoice value) => state = value;
}

class RememberCallerChoiceController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final outboundLeadDraftProvider =
    NotifierProvider<OutboundLeadDraftController, OutboundLeadDraft>(
      OutboundLeadDraftController.new,
    );

class OutboundLeadDraftController extends Notifier<OutboundLeadDraft> {
  @override
  OutboundLeadDraft build() => const OutboundLeadDraft();

  void updateName(String value) => state = state.copyWith(name: value);
  void updatePhone(String value) => state = state.copyWith(phone: value);
  void updateReason(String value) => state = state.copyWith(reason: value);
  void updateSource(String value) => state = state.copyWith(source: value);
}

// ─── Lead stage pipeline ─────────────────────────────────────────────────────

/// Per-lead CRM pipeline stage, stored locally in SharedPreferences.
/// Key: `lead_stages_v1` → JSON object { leadId: stageName }.
final leadStageProvider =
    NotifierProvider<LeadStageController, Map<String, LeadStage>>(
  LeadStageController.new,
);

class LeadStageController extends Notifier<Map<String, LeadStage>> {
  static const _key = 'lead_stages_v1';

  @override
  Map<String, LeadStage> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final e in map.entries) e.key: LeadStageX.fromValue(e.value as String?),
      };
    } catch (_) {}
  }

  Future<void> setStage(String leadId, LeadStage stage) async {
    state = {...state, leadId: stage};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({for (final e in state.entries) e.key: e.value.value}),
    );
  }

  LeadStage stageFor(String leadId) => state[leadId] ?? LeadStage.newLead;
}

// ─── Attendance (clock in/out) ────────────────────────────────────────────────

/// UI state for the Profile screen's Attendance card: today's record plus
/// in-flight/error flags for the check-in / check-out actions.
class AttendanceState {
  const AttendanceState({
    this.record,
    this.loading = false,
    this.actionInProgress = false,
    this.error,
  });

  /// Today's attendance record, or null until the first fetch resolves.
  final AttendanceRecord? record;

  /// True while the initial `today()` fetch is in flight.
  final bool loading;

  /// True while a check-in/check-out request is in flight.
  final bool actionInProgress;

  /// Last error message to surface via a snackbar, if any.
  final String? error;

  AttendanceState copyWith({
    AttendanceRecord? record,
    bool? loading,
    bool? actionInProgress,
    String? error,
    bool clearError = false,
  }) {
    return AttendanceState(
      record: record ?? this.record,
      loading: loading ?? this.loading,
      actionInProgress: actionInProgress ?? this.actionInProgress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Today's attendance record + check-in/check-out actions for the Profile
/// screen's Attendance card.
final attendanceProvider =
    NotifierProvider<AttendanceController, AttendanceState>(
  AttendanceController.new,
);

class AttendanceController extends Notifier<AttendanceState> {
  @override
  AttendanceState build() {
    _load();
    return const AttendanceState(loading: true);
  }

  Future<void> _load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final record = await ref.read(attendanceRepositoryProvider).today();
      state = state.copyWith(record: record, loading: false);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  /// Re-fetch today's record (e.g. pull-to-refresh).
  Future<void> refresh() => _load();

  /// `POST /api/attendance/check-in`. A 409 (already checked in) is treated
  /// as harmless — it just means another tap/device beat this one there, so
  /// state is refreshed instead of surfacing a scary error.
  Future<void> checkIn() async {
    state = state.copyWith(actionInProgress: true, clearError: true);
    try {
      final record = await ref.read(attendanceRepositoryProvider).checkIn();
      state = state.copyWith(record: record, actionInProgress: false);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _load();
        return;
      }
      state = state.copyWith(actionInProgress: false, error: e.message);
    }
  }

  /// `POST /api/attendance/check-out`. A 409 (already checked out) is
  /// treated the same harmless way as [checkIn]'s race; a 404 (no check-in
  /// yet today) is surfaced since that's a genuine usage error.
  Future<void> checkOut() async {
    state = state.copyWith(actionInProgress: true, clearError: true);
    try {
      final record = await ref.read(attendanceRepositoryProvider).checkOut();
      state = state.copyWith(record: record, actionInProgress: false);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _load();
        return;
      }
      state = state.copyWith(actionInProgress: false, error: e.message);
    }
  }
}
