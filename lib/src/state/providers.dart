import 'dart:async' show Timer, unawaited;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/api/api_exception.dart';
import '../core/api/http_api_client.dart';
import '../data/attendance_repository.dart';
import '../data/follow_up_repository.dart';
import '../data/lead_repository.dart';
import '../data/mock_leads.dart';
import '../data/org_profile_repository.dart';
import '../models/attendance_record.dart';
import '../models/lead.dart';
import '../services/local_call_store.dart';
import '../services/local_follow_up_store.dart';
import '../services/local_lead_override_store.dart';
import '../services/session_store.dart';

// ─── Backend wiring ───────────────────────────────────────────────────────────

/// The HTTP transport. Swap the implementation here (or override in tests)
/// without touching call sites. Reads the session's JWT fresh on every
/// request so login/logout take effect immediately. Every request's outcome
/// also feeds [serverReachableProvider] so the app-wide "can't reach server"
/// banner (see `app.dart`) reflects real connectivity, not just the leads
/// screen's own fallback-to-mock-data path.
final apiClientProvider = Provider<ApiClient>(
  (ref) => HttpApiClient(
    getToken: () => ref.read(sessionProvider).token,
    onConnectivityOk: () => ref.read(serverReachableProvider.notifier).markReachable(),
    onConnectivityIssue: () => ref.read(serverReachableProvider.notifier).markUnreachable(),
  ),
);

/// Whether the backend was reachable as of the most recent request — true
/// (optimistic) until proven otherwise. Drives the global "no server
/// connection" banner shown over every screen (see `app.dart`).
final serverReachableProvider =
    NotifierProvider<ServerReachabilityController, bool>(
      ServerReachabilityController.new,
    );

class ServerReachabilityController extends Notifier<bool> {
  Timer? _retryTimer;

  @override
  bool build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
    });
    return true;
  }

  /// Called by [HttpApiClient] whenever a request gets any response below
  /// 500 — proof the server is up, whatever the request's own outcome.
  void markReachable() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!state) state = true;
  }

  /// Called by [HttpApiClient] on a network-layer failure (timeout, socket
  /// error, DNS/transport error) or a 5xx response. Schedules a background
  /// `/health` retry loop so the banner clears itself without the user
  /// having to do anything, once the server/network recovers.
  void markUnreachable() {
    if (state) state = false;
    _scheduleRetry();
  }

  /// Forces an immediate reachability check — wired to the banner's Retry
  /// button so tapping it doesn't just wait for the next background tick.
  Future<void> retryNow() => _attemptRetry();

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 6), _attemptRetry);
  }

  Future<void> _attemptRetry() async {
    if (await _pingHealth()) {
      markReachable();
    } else if (!state) {
      _scheduleRetry();
    }
  }

  static Future<bool> _pingHealth() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 6));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}

/// Maps the FastAPI "AI layer" responses into the app's domain models.
final leadRepositoryProvider = Provider<LeadRepository>(
  (ref) => LeadRepository(
    ref.watch(apiClientProvider),
    getToken: () => ref.read(sessionProvider).token,
  ),
);

/// Talks to the attendance (clock in/out) endpoints.
final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(apiClientProvider)),
);

/// Talks to the follow-up endpoints.
final followUpRepositoryProvider = Provider<FollowUpRepository>(
  (ref) => FollowUpRepository(ref.watch(apiClientProvider)),
);

/// Talks to the org-profile endpoint.
final orgProfileRepositoryProvider = Provider<OrgProfileRepository>(
  (ref) => OrgProfileRepository(ref.watch(apiClientProvider)),
);

/// The telecaller's org (name/logo/address/etc.), set up by the founder on
/// the web app — feeds the Profile screen's org card. Resolves to null (not
/// an error state) when mock data is on or the fetch fails, so the screen can
/// quietly fall back to the org name already carried on [sessionProvider].
final orgProfileProvider = FutureProvider<OrgProfile?>((ref) async {
  if (ApiConfig.useMockData) return null;
  try {
    return await ref.read(orgProfileRepositoryProvider).fetch();
  } catch (_) {
    return null;
  }
});

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

/// True while [LeadsController] is running its initial/refresh fetch —
/// screens watch this to show a shimmer skeleton instead of an empty list.
final leadsLoadingProvider =
    NotifierProvider<LeadsLoadingController, bool>(LeadsLoadingController.new);

class LeadsLoadingController extends Notifier<bool> {
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
    // Deferred to a microtask: `_load` mutates `leadsLoadingProvider`
    // synchronously as its first step, and Riverpod forbids a provider from
    // modifying another provider while it's still inside its own `build()`.
    Future.microtask(_load);
    return const [];
  }

  Future<void> _loadOverrides() async {
    _overrides = await ref.read(localLeadOverrideStoreProvider).loadAll();
    if (_overrides.isNotEmpty) state = [for (final l in state) _withOverride(l)];
  }

  Lead _withOverride(Lead lead) =>
      _overrides[lead.id]?.applyTo(lead) ?? lead;

  Future<void> _load() async {
    ref.read(leadsLoadingProvider.notifier).set(true);
    _overrides = await ref.read(localLeadOverrideStoreProvider).loadAll();
    try {
      final fetched = await ref.read(leadRepositoryProvider).fetchInbox();
      state = [for (final l in fetched) _withOverride(l)];
      ref.read(leadsUsingFallbackProvider.notifier).set(false);
    } catch (_) {
      // Backend unreachable. Only fall back to mock data if nothing real has
      // ever loaded — a transient failure on a later refresh (expired token,
      // one-off 5xx) must NOT clobber a working inbox with fake leads; that
      // was the "stuck showing stale/cached data" bug.
      if (state.isEmpty) {
        state = [for (final l in mockLeads) _withOverride(l)];
        ref.read(leadsUsingFallbackProvider.notifier).set(true);
      }
    } finally {
      ref.read(leadsLoadingProvider.notifier).set(false);
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
      final result =
          await ref.read(leadRepositoryProvider).leadDetailWithStage(contactKey);
      state = [
        for (final lead in state)
          if (lead.id == contactKey) _withOverride(result.lead) else lead,
      ];
      // Persist this lead's confirmed backend call history into the local call
      // log so those calls survive a restart and show in My Calls without the
      // lead having to stay open. Upsert/merge is handled downstream.
      unawaited(ref
          .read(localCallsProvider.notifier)
          .ingest(callEntriesFromLead(result.lead)));
      // Read back the authoritative kanban stage (server wins) so a move made on
      // the web dashboard is reflected here too. Fail-soft / fire-and-forget.
      final stage = result.stage;
      if (stage != null && stage.isNotEmpty) {
        unawaited(ref.read(leadStageProvider.notifier).syncFromServer(contactKey, stage));
      }
    } catch (_) {/* keep the thin card */}
  }

  /// Recompute a contact's memory bubble from all their calls, then re-enrich
  /// so the refreshed bubble shows immediately. Throws on failure so the caller
  /// can surface a toast (unlike [enrich], which is fire-and-forget).
  Future<void> rebuildMemory(String contactKey) async {
    if (ApiConfig.useMockData || contactKey.isEmpty) return;
    await ref.read(leadRepositoryProvider).rebuildMemory(contactKey);
    await enrich(contactKey);
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

/// True while [FollowUpController] is running its initial/refresh load —
/// screens watch this to show a shimmer skeleton instead of an empty list.
final followUpsLoadingProvider = NotifierProvider<FollowUpsLoadingController, bool>(
  FollowUpsLoadingController.new,
);

class FollowUpsLoadingController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// Merges the local follow-up list with the backend's authoritative list so
/// status changes made on another device (same account) propagate:
///  - local-only tasks (no backendId yet — created offline) are kept as-is;
///  - tasks known on both sides adopt the backend's status/schedule, keeping
///    this device's richer display fields. "Done" is sticky (once either side
///    says done it stays done) so a local done still syncing isn't reverted;
///  - tasks that have a backendId but are gone from the backend were deleted
///    on another device → dropped;
///  - backend-only tasks (created elsewhere) are added, with the lead's real
///    name/phone resolved from the inbox where possible.
///
/// Pure (no I/O) so it can be unit-tested directly. [remote] must have been
/// fetched with completed follow-ups included, or done/deleted tasks would be
/// indistinguishable from ones that never existed.
List<FollowUpTask> reconcileFollowUps(
  List<FollowUpTask> local,
  List<FollowUpTask> remote,
  Map<String, Lead> leadsById,
) {
  final remoteById = {
    for (final r in remote)
      if (r.backendId != null) r.backendId!: r,
  };
  final result = <FollowUpTask>[];
  final kept = <String>{};

  for (final t in local) {
    final bid = t.backendId;
    if (bid == null) {
      result.add(t); // never synced — leave it alone
      continue;
    }
    final r = remoteById[bid];
    if (r == null) continue; // deleted on another device
    kept.add(bid);
    final done =
        t.status == FollowUpStatus.done || r.status == FollowUpStatus.done;
    final scheduledAt = r.scheduledAt ?? t.scheduledAt;
    result.add(t.copyWith(
      status: done ? FollowUpStatus.done : r.status,
      scheduledAt: scheduledAt,
      dueToday: done ? false : _followUpIsToday(scheduledAt),
    ));
  }

  for (final r in remote) {
    final bid = r.backendId;
    if (bid == null || kept.contains(bid)) continue;
    final lead = r.leadId == null ? null : leadsById[r.leadId];
    final done = r.status == FollowUpStatus.done;
    result.add(r.copyWith(
      leadName: lead?.name ?? r.leadName,
      phone: lead?.phone ?? r.phone,
      dueToday: done ? false : _followUpIsToday(r.scheduledAt),
    ));
  }

  return result;
}

bool _followUpIsToday(DateTime? dt) {
  if (dt == null) return false;
  final now = DateTime.now();
  return dt.year == now.year && dt.month == now.month && dt.day == now.day;
}

class FollowUpController extends Notifier<List<FollowUpTask>> {
  @override
  List<FollowUpTask> build() {
    // Deferred to a microtask: `_load` mutates `followUpsLoadingProvider`
    // synchronously as its first step, and Riverpod forbids a provider from
    // modifying another provider while it's still inside its own `build()`.
    Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    ref.read(followUpsLoadingProvider.notifier).set(true);
    try {
      final local = await ref.read(localFollowUpStoreProvider).loadAll();
      state = local;
      // Reconcile against the backend so status changes made on another device
      // (same telecaller account) propagate: a follow-up marked done or deleted
      // elsewhere is reflected here, not just newly-created ones. Fail-soft —
      // any error leaves the local list untouched.
      try {
        final remote = await ref
            .read(followUpRepositoryProvider)
            .list(includeCompleted: true);
        final leadsById = {for (final l in ref.read(leadsProvider)) l.id: l};
        final reconciled = reconcileFollowUps(local, remote, leadsById);
        state = reconciled;
        // Persist the merged view so it survives a restart without re-fetching.
        await ref.read(localFollowUpStoreProvider).replaceAll(reconciled);
      } catch (_) {
        // Offline / backend down — local remains the source of truth.
      }
    } finally {
      ref.read(followUpsLoadingProvider.notifier).set(false);
    }
  }


  /// Pull-to-refresh: re-run the local+remote merge so follow-ups created or
  /// synced from another device (same telecaller account) show up here without
  /// an app restart.
  Future<void> refresh() => _load();

  /// Local write is the source of truth for this screen (matches this app's
  /// existing fail-soft pattern); the backend sync is best-effort so a
  /// flaky/offline connection never blocks scheduling a follow-up.
  Future<void> schedule(FollowUpTask task) async {
    await ref.read(localFollowUpStoreProvider).add(task);
    unawaited(_load());
    try {
      final backendId = await ref.read(followUpRepositoryProvider).create(
        leadId: task.leadId,
        note: task.taskText,
        dueAt: task.scheduledAt ?? DateTime.now(),
      );
      if (backendId.isNotEmpty) {
        await ref.read(localFollowUpStoreProvider).update(
          task.copyWith(backendId: backendId),
        );
        unawaited(_load());
      }
    } catch (_) {
      // Fail soft — stays local-only until the next successful sync.
    }
  }

  Future<void> markDone(String id) async {
    final backendId = _backendIdFor(id);
    await ref.read(localFollowUpStoreProvider).markDone(id);
    // Reflect immediately. A concurrent reconcile is safe here — "done" is
    // sticky, so even if the backend hasn't recorded it yet the local done
    // isn't reverted.
    unawaited(_load());
    if (backendId != null) {
      try {
        await ref.read(followUpRepositoryProvider).setCompleted(backendId, true);
      } catch (_) {
        // Fail soft — local state already reflects "done".
      }
    }
  }

  Future<void> delete(String id) async {
    final backendId = _backendIdFor(id);
    await ref.read(localFollowUpStoreProvider).delete(id);
    // Reflect the removal immediately in memory.
    state = [for (final t in state) if (t.id != id) t];
    if (backendId == null) return; // local-only task, nothing to sync
    try {
      await ref.read(followUpRepositoryProvider).delete(backendId);
      // Only reconcile AFTER the backend delete lands — otherwise the reconcile
      // would see the task still present remotely and re-add it.
      unawaited(_load());
    } catch (_) {
      // Fail soft — it's gone locally; a later successful reconcile (once the
      // backend delete goes through, or if another device already removed it)
      // will finish the job.
    }
  }

  String? _backendIdFor(String id) {
    for (final task in state) {
      if (task.id == id) return task.backendId;
    }
    return null;
  }
}

/// Global call log. Reads ONLY the persisted [localCallsProvider], which holds
/// calls this device has real evidence for (a recording was found for a call
/// that ended) plus backend history that's been ingested for leads the
/// telecaller actually opened. Backend history is no longer merged live off
/// every enriched lead — that made calls appear merely because a lead was
/// opened, and vanish again on restart (both reported bugs). Sorted
/// newest-first.
final callLogProvider = Provider<List<CallLogEntry>>((ref) {
  final entries = [...ref.watch(localCallsProvider)];
  entries.sort((a, b) => b.calledAt.compareTo(a.calledAt));
  return entries;
});

/// Builds persist-able call-log entries from an enriched lead's backend call
/// history (only calls with a real timestamp).
List<CallLogEntry> callEntriesFromLead(Lead lead) => [
      for (final c in lead.history)
        if (c.calledAt != null)
          CallLogEntry(
            id: c.callId ?? '${lead.id}_${c.calledAt!.millisecondsSinceEpoch}',
            leadName: lead.name,
            phone: lead.phone,
            intent: lead.intent,
            source: lead.source,
            duration: c.duration,
            score: c.score,
            // Backend timestamps come back UTC — store as local so the calls
            // screen's day-grouping and time formatting (which read the
            // DateTime's own fields) show the real local call time.
            calledAt: c.calledAt!.toLocal(),
            leadId: lead.id,
            callId: c.callId,
          ),
    ];

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

  Future<void> setStage(
    String leadId,
    LeadStage stage, {
    int? dealValue,
    int? listPrice,
    double? discountPct,
  }) async {
    // Optimistic local update first (keeps the UI responsive / offline-usable,
    // matching this app's existing fail-soft pattern), then push to the
    // backend so the founder's web Kanban sees the move too.
    state = {...state, leadId: stage};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({for (final e in state.entries) e.key: e.value.value}),
    );
    try {
      await ref.read(leadRepositoryProvider).updateLeadStage(
        leadId,
        stage,
        dealValue: dealValue,
        listPrice: listPrice,
        discountPct: discountPct,
      );
    } catch (_) {
      // Fail soft: local state already reflects the move; the next successful
      // sync (or a future outbox/retry mechanism) will reconcile the backend.
    }
  }

  LeadStage stageFor(String leadId) => state[leadId] ?? LeadStage.newLead;

  /// Read-back: adopt the authoritative server stage (e.g. moved on the web
  /// dashboard) when it differs from what's stored locally. Server wins, mirroring
  /// the follow-ups read-back — the local value was itself pushed to the server on
  /// the last move, so a divergence means someone else changed it.
  Future<void> syncFromServer(String leadId, String serverStageValue) async {
    final stage = LeadStageX.fromValue(serverStageValue);
    if (state[leadId] == stage) return;
    state = {...state, leadId: stage};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({for (final e in state.entries) e.key: e.value.value}),
    );
  }
}

// ─── Attendance (clock in/out) ────────────────────────────────────────────────

/// UI state for the Profile screen's Attendance card: today's record plus
/// in-flight/error flags for the check-in / check-out actions.
class AttendanceState {
  const AttendanceState({
    this.record,
    this.openPastShifts = const [],
    this.loading = false,
    this.actionInProgress = false,
    this.error,
  });

  /// Today's attendance record, or null until the first fetch resolves.
  final AttendanceRecord? record;

  /// Prior-day shifts the telecaller never checked out of (forgotten), so the
  /// Profile screen can prompt them to close each one.
  final List<AttendanceRecord> openPastShifts;

  /// True while the initial `today()` fetch is in flight.
  final bool loading;

  /// True while a check-in/check-out request is in flight.
  final bool actionInProgress;

  /// Last error message to surface via a snackbar, if any.
  final String? error;

  AttendanceState copyWith({
    AttendanceRecord? record,
    List<AttendanceRecord>? openPastShifts,
    bool? loading,
    bool? actionInProgress,
    String? error,
    bool clearError = false,
  }) {
    return AttendanceState(
      record: record ?? this.record,
      openPastShifts: openPastShifts ?? this.openPastShifts,
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
    // _load() touches `state` on its very first line (before any `await`), and Dart
    // runs an async function synchronously up to its first `await` — so calling it
    // directly here executes that `state` read/write while build() is still on the
    // stack, before Riverpod has finished initializing this provider ("Tried to read
    // the state of an uninitialized provider"). Future.microtask defers it to run
    // right after build() returns, once the provider is actually initialized.
    Future.microtask(_load);
    return const AttendanceState(loading: true);
  }

  Future<void> _load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(attendanceRepositoryProvider);
      final record = await repo.today();
      // Prior-day shifts the telecaller never closed. Best-effort: an older
      // backend without /mine must not break the card, so swallow its errors.
      List<AttendanceRecord> openPast = const [];
      try {
        final mine = await repo.mine(days: 7);
        openPast = mine
            .where((r) =>
                r.checkInAt != null && r.checkOutAt == null && r.id != record.id)
            .toList();
      } on ApiException {
        openPast = const [];
      }
      state = state.copyWith(
        record: record,
        openPastShifts: openPast,
        loading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  /// Re-fetch today's record (e.g. pull-to-refresh).
  Future<void> refresh() => _load();

  /// Close a shift from a previous day the telecaller forgot to check out of.
  /// A 409 (already closed) is treated as a harmless race and just refreshes.
  Future<void> closePastShift(String recordId) async {
    state = state.copyWith(actionInProgress: true, clearError: true);
    try {
      await ref.read(attendanceRepositoryProvider).closeShift(recordId);
      await _load();
      state = state.copyWith(actionInProgress: false);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _load();
        state = state.copyWith(actionInProgress: false);
        return;
      }
      state = state.copyWith(actionInProgress: false, error: e.message);
    }
  }

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
        // _load()'s copyWith doesn't touch actionInProgress, so it would
        // otherwise stay stuck true (from the line above) forever — leaving
        // the Check In/Out button permanently disabled/spinning.
        state = state.copyWith(actionInProgress: false);
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
        // See the matching comment in checkIn() — actionInProgress must be
        // reset explicitly or the button stays stuck busy after a 409 race.
        state = state.copyWith(actionInProgress: false);
        return;
      }
      state = state.copyWith(actionInProgress: false, error: e.message);
    }
  }
}
