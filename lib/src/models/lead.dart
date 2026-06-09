enum LeadTemperature { hot, warm, cold }

enum LeadSource { meta, referral, event, inbound, website }

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
}

class ScriptStep {
  const ScriptStep({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

class Objection {
  const Objection({required this.question, required this.response});

  final String question;
  final String response;
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
}

class CallRecord {
  const CallRecord({
    required this.title,
    required this.duration,
    required this.score,
  });

  final String title;
  final Duration duration;
  final int score;
}

class OutboundLeadDraft {
  const OutboundLeadDraft({
    this.name = 'Rakesh Sharma',
    this.phone = '+91 98765 43210',
    this.reason = 'Follow-up from event',
    this.source = 'Event',
    this.hasDuplicate = true,
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
}
