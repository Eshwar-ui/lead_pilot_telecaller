enum LeadTemperature { hot, warm, cold }

enum LeadSource { meta, referral, event, inbound, website, organic }

/// CRM pipeline stages for a lead, set manually by the telecaller.
///
/// Mirrors the backend's `Lead.pipeline_stage` / `KANBAN_STAGES` exactly (see
/// `dashboard.py`) so a stage set here round-trips through
/// `PATCH /api/leads/by-contact/{contact_key}/stage` and shows up correctly on
/// the founder web Kanban board, and vice versa.
enum LeadStage {
  newLead,
  assigned,
  contacted,
  interested,
  proposalSent,
  negotiation,
  closedWon,
  closedLost,
  junk,
}

extension LeadStageX on LeadStage {
  /// Wire value — must match the backend's KANBAN_STAGES strings exactly
  /// (e.g. "Proposal Sent", not "proposalSent").
  String get value => switch (this) {
    LeadStage.newLead => 'New',
    LeadStage.assigned => 'Assigned',
    LeadStage.contacted => 'Contacted',
    LeadStage.interested => 'Interested',
    LeadStage.proposalSent => 'Proposal Sent',
    LeadStage.negotiation => 'Negotiation',
    LeadStage.closedWon => 'Closed Won',
    LeadStage.closedLost => 'Closed Lost',
    LeadStage.junk => 'Junk',
  };

  String get label => value;

  /// Terminal, negative-outcome stages — styled the same way `dead` used to be.
  bool get isTerminalNegative =>
      this == LeadStage.closedLost || this == LeadStage.junk;

  static LeadStage fromValue(String? v) => switch (v) {
    'New' => LeadStage.newLead,
    'Assigned' => LeadStage.assigned,
    'Contacted' => LeadStage.contacted,
    'Interested' => LeadStage.interested,
    'Proposal Sent' => LeadStage.proposalSent,
    'Negotiation' => LeadStage.negotiation,
    'Closed Won' => LeadStage.closedWon,
    'Closed Lost' => LeadStage.closedLost,
    'Junk' => LeadStage.junk,
    _ => LeadStage.newLead,
  };
}

extension LeadTemperatureX on LeadTemperature {
  /// Wire value used in API payloads, e.g. "hot".
  String get value => name;

  static LeadTemperature fromValue(String? value) =>
      LeadTemperature.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LeadTemperature.cold,
      );
}

extension LeadSourceX on LeadSource {
  String get displayName => switch (this) {
    LeadSource.meta => 'Meta',
    LeadSource.referral => 'Referral',
    LeadSource.event => 'Event',
    LeadSource.inbound => 'Inbound',
    LeadSource.website => 'Website',
    LeadSource.organic => 'Organic',
  };

  /// Wire value used in API payloads, e.g. "meta".
  String get value => name;

  static LeadSource fromValue(String? value) => LeadSource.values.firstWhere(
    (e) => e.name == value,
    orElse: () => LeadSource.organic,
  );
}

class Lead {
  const Lead({
    required this.id,
    required this.name,
    required this.phone,
    required this.score,
    required this.temperature,
    required this.source,
    required this.intent,
    required this.lastContact,
    required this.totalCalls,
    required this.averageScore,
    required this.memory,
    required this.script,
    required this.objections,
    required this.checklist,
    required this.history,
    this.propertyInterest,
  });

  final String id;
  final String name;
  final String phone;
  final int score;
  final LeadTemperature temperature;
  final LeadSource source;
  final String intent;
  final DateTime lastContact;
  final int totalCalls;
  final int averageScore;
  final List<MemoryInsight> memory;
  final AiScript script;
  final List<Objection> objections;
  final List<ChecklistItem> checklist;
  final List<CallRecord> history;
  /// Short topic shown in the lead tile timestamp, e.g. "Luxury Villas Search".
  final String? propertyInterest;

  /// Safe placeholder used while the inbox is loading or empty, so providers
  /// that must return a non-null [Lead] never throw on an empty list.
  factory Lead.empty() => Lead(
    id: '',
    name: '',
    phone: '',
    score: 0,
    temperature: LeadTemperature.cold,
    source: LeadSource.organic,
    intent: '',
    lastContact: DateTime.fromMillisecondsSinceEpoch(0),
    totalCalls: 0,
    averageScore: 0,
    memory: const [],
    script: const AiScript(
      generatedAgo: '',
      openingLine: '',
      keyPoints: [],
      steps: [],
    ),
    objections: const [],
    checklist: const [],
    history: const [],
  );

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    score: (json['score'] as num?)?.toInt() ?? 0,
    temperature: LeadTemperatureX.fromValue(json['temperature'] as String?),
    source: LeadSourceX.fromValue(json['source'] as String?),
    intent: json['intent'] as String? ?? '',
    lastContact: _parseDate(json['last_contact']),
    totalCalls: (json['total_calls'] as num?)?.toInt() ?? 0,
    averageScore: (json['average_score'] as num?)?.toInt() ?? 0,
    memory: _list(json['memory'], MemoryInsight.fromJson),
    script: json['script'] is Map<String, dynamic>
        ? AiScript.fromJson(json['script'] as Map<String, dynamic>)
        : const AiScript(
            generatedAgo: '',
            openingLine: '',
            keyPoints: [],
            steps: [],
          ),
    objections: _list(json['objections'], Objection.fromJson),
    checklist: _list(json['checklist'], ChecklistItem.fromJson),
    history: _list(json['history'], CallRecord.fromJson),
    propertyInterest: json['property_interest'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'score': score,
    'temperature': temperature.value,
    'source': source.value,
    'intent': intent,
    'last_contact': lastContact.toIso8601String(),
    'total_calls': totalCalls,
    'average_score': averageScore,
    'memory': memory.map((e) => e.toJson()).toList(),
    'script': script.toJson(),
    'objections': objections.map((e) => e.toJson()).toList(),
    'checklist': checklist.map((e) => e.toJson()).toList(),
    'history': history.map((e) => e.toJson()).toList(),
    'property_interest': propertyInterest,
  };
}

class MemoryInsight {
  const MemoryInsight({
    required this.text,
    required this.callLabel,
    required this.colorKey,
  });

  final String text;
  final String callLabel;
  final String colorKey;

  factory MemoryInsight.fromJson(Map<String, dynamic> json) => MemoryInsight(
    text: json['text'] as String? ?? '',
    callLabel: json['call_label'] as String? ?? '',
    colorKey: json['color_key'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'call_label': callLabel,
    'color_key': colorKey,
  };
}

class AiScript {
  const AiScript({
    required this.generatedAgo,
    required this.openingLine,
    required this.keyPoints,
    required this.steps,
  });

  final String generatedAgo;
  final String openingLine;
  final List<String> keyPoints;
  final List<ScriptStep> steps;

  factory AiScript.fromJson(Map<String, dynamic> json) => AiScript(
    generatedAgo: json['generated_ago'] as String? ?? '',
    openingLine: json['opening_line'] as String? ?? '',
    keyPoints:
        (json['key_points'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
    steps: _list(json['steps'], ScriptStep.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'generated_ago': generatedAgo,
    'opening_line': openingLine,
    'key_points': keyPoints,
    'steps': steps.map((e) => e.toJson()).toList(),
  };
}

class ScriptStep {
  const ScriptStep({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  factory ScriptStep.fromJson(Map<String, dynamic> json) => ScriptStep(
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'title': title, 'subtitle': subtitle};
}

class Objection {
  const Objection({required this.question, required this.response});

  final String question;
  final String response;

  factory Objection.fromJson(Map<String, dynamic> json) => Objection(
    question: json['question'] as String? ?? '',
    response: json['response'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'question': question, 'response': response};
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    required this.completed,
  });

  final String id;
  final String text;
  final bool completed;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    completed: json['completed'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'completed': completed,
  };
}

class CallRecord {
  const CallRecord({
    required this.title,
    required this.duration,
    required this.score,
    this.calledAt,
    this.leadId,
    this.callId,
  });

  final String title;
  final Duration duration;
  final int score;
  final DateTime? calledAt;
  /// ID of the associated [Lead] — used to build the global call log.
  final String? leadId;
  /// Backend `call_id` for this specific call. Null for a locally-placed call
  /// that hasn't been captured/uploaded yet — those have no stored transcript.
  final String? callId;

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
    title: json['title'] as String? ?? '',
    duration: Duration(seconds: (json['duration_seconds'] as num?)?.toInt() ?? 0),
    score: (json['score'] as num?)?.toInt() ?? 0,
    calledAt: json['called_at'] != null
        ? DateTime.tryParse(json['called_at'] as String)
        : null,
    leadId: json['lead_id'] as String?,
    callId: json['call_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'duration_seconds': duration.inSeconds,
    'score': score,
    'called_at': calledAt?.toIso8601String(),
    'lead_id': leadId,
    'call_id': callId,
  };
}

// ─── Follow-up tasks ──────────────────────────────────────────────────────────

enum FollowUpStatus { overdue, pending, done }

extension FollowUpStatusX on FollowUpStatus {
  /// Wire value used in API payloads, e.g. "overdue".
  String get value => name;

  static FollowUpStatus fromValue(String? value) =>
      FollowUpStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => FollowUpStatus.pending,
      );
}

class FollowUpTask {
  const FollowUpTask({
    required this.id,
    required this.taskText,
    required this.leadName,
    this.phone,
    this.leadId,
    required this.status,
    this.dueLabel,
    this.dueToday = false,
    this.scheduledAt,
    this.note,
    this.backendId,
  });

  final String id;
  final String taskText;
  final String leadName;
  final String? phone;
  /// ID of the associated [Lead] — used for navigation to lead detail.
  final String? leadId;
  final FollowUpStatus status;
  final String? dueLabel;
  /// True when this task is due on today's date (used for tab filtering).
  final bool dueToday;
  /// When the follow-up is scheduled — null means unscheduled.
  final DateTime? scheduledAt;
  /// Optional telecaller note saved alongside the scheduled call.
  final String? note;
  /// The backend `FollowUp.id`, set once this task has synced to
  /// `/api/follow-ups`. Null means it only exists locally so far (created
  /// offline, or the initial sync call failed) — mark-done/delete then only
  /// update the local copy until a future sync reconciles it.
  final String? backendId;

  FollowUpTask copyWith({
    String? id,
    String? taskText,
    String? leadName,
    String? phone,
    String? leadId,
    FollowUpStatus? status,
    String? dueLabel,
    bool? dueToday,
    DateTime? scheduledAt,
    String? note,
    String? backendId,
  }) => FollowUpTask(
    id: id ?? this.id,
    taskText: taskText ?? this.taskText,
    leadName: leadName ?? this.leadName,
    phone: phone ?? this.phone,
    leadId: leadId ?? this.leadId,
    status: status ?? this.status,
    dueLabel: dueLabel ?? this.dueLabel,
    dueToday: dueToday ?? this.dueToday,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    note: note ?? this.note,
    backendId: backendId ?? this.backendId,
  );

  factory FollowUpTask.fromJson(Map<String, dynamic> json) => FollowUpTask(
    id: json['id'] as String? ?? '',
    taskText: json['task_text'] as String? ?? '',
    leadName: json['lead_name'] as String? ?? '',
    phone: json['phone'] as String?,
    leadId: json['lead_id'] as String?,
    status: FollowUpStatusX.fromValue(json['status'] as String?),
    dueLabel: json['due_label'] as String?,
    dueToday: json['due_today'] as bool? ?? false,
    scheduledAt: json['scheduled_at'] != null
        ? DateTime.tryParse(json['scheduled_at'] as String)
        : null,
    note: json['note'] as String?,
    backendId: json['backend_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'task_text': taskText,
    'lead_name': leadName,
    'phone': phone,
    'lead_id': leadId,
    'status': status.value,
    'due_label': dueLabel,
    'due_today': dueToday,
    'scheduled_at': scheduledAt?.toIso8601String(),
    'note': note,
    'backend_id': backendId,
  };
}

// ─── Global call log ──────────────────────────────────────────────────────────

class CallLogEntry {
  const CallLogEntry({
    required this.id,
    required this.leadName,
    required this.phone,
    required this.intent,
    required this.source,
    required this.duration,
    required this.score,
    required this.calledAt,
    this.isInbound = false,
    this.leadId,
    this.callId,
  });

  final String id;
  final String leadName;
  final String phone;
  final String intent;
  final LeadSource source;
  final Duration duration;
  final int score;
  final DateTime calledAt;
  final bool isInbound;
  /// Lead ID — used to navigate from call log to lead detail.
  final String? leadId;
  /// Backend `call_id` once the recording has been uploaded/transcribed. Null
  /// for a call only observed locally so far. Used as the stable identity when
  /// de-duplicating the persisted call log against backend history.
  final String? callId;

  CallLogEntry copyWith({
    Duration? duration,
    int? score,
    DateTime? calledAt,
    String? callId,
    String? leadName,
    String? phone,
    String? intent,
    LeadSource? source,
  }) => CallLogEntry(
    id: id,
    leadName: leadName ?? this.leadName,
    phone: phone ?? this.phone,
    intent: intent ?? this.intent,
    source: source ?? this.source,
    duration: duration ?? this.duration,
    score: score ?? this.score,
    calledAt: calledAt ?? this.calledAt,
    isInbound: isInbound,
    leadId: leadId,
    callId: callId ?? this.callId,
  );

  factory CallLogEntry.fromJson(Map<String, dynamic> json) => CallLogEntry(
    id: json['id'] as String? ?? '',
    leadName: json['lead_name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    intent: json['intent'] as String? ?? '',
    source: LeadSourceX.fromValue(json['source'] as String?),
    duration: Duration(seconds: (json['duration_seconds'] as num?)?.toInt() ?? 0),
    score: (json['score'] as num?)?.toInt() ?? 0,
    calledAt: _parseDate(json['called_at']),
    isInbound: json['is_inbound'] as bool? ?? false,
    leadId: json['lead_id'] as String?,
    callId: json['call_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'lead_name': leadName,
    'phone': phone,
    'intent': intent,
    'source': source.value,
    'duration_seconds': duration.inSeconds,
    'score': score,
    'called_at': calledAt.toIso8601String(),
    'is_inbound': isInbound,
    'lead_id': leadId,
    'call_id': callId,
  };
}

// ─── Outbound draft ───────────────────────────────────────────────────────────

class OutboundLeadDraft {
  const OutboundLeadDraft({
    this.name = '',
    this.phone = '',
    this.reason = '',
    this.source = '',
    this.hasDuplicate = false,
  });

  final String name;
  final String phone;
  final String reason;
  final String source;
  final bool hasDuplicate;

  OutboundLeadDraft copyWith({
    String? name,
    String? phone,
    String? reason,
    String? source,
    bool? hasDuplicate,
  }) {
    return OutboundLeadDraft(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      reason: reason ?? this.reason,
      source: source ?? this.source,
      hasDuplicate: hasDuplicate ?? this.hasDuplicate,
    );
  }

  factory OutboundLeadDraft.fromJson(Map<String, dynamic> json) =>
      OutboundLeadDraft(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        source: json['source'] as String? ?? '',
        hasDuplicate: json['has_duplicate'] as bool? ?? false,
      );

  /// Shape sent to the backend when creating an outbound lead.
  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'reason': reason,
    'source': source,
  };
}

// ─── JSON helpers ─────────────────────────────────────────────────────────────

/// Maps a JSON list (or null) into a typed list using [fromJson] per element.
List<T> _list<T>(
  Object? raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList(growable: false);
}

/// Parses an ISO-8601 date string, falling back to the epoch when absent.
DateTime _parseDate(Object? raw) {
  if (raw is String) {
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
