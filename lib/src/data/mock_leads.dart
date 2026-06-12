import '../models/lead.dart';

/// Seed data. Static demo leads/tasks/calls have been cleared — the app starts
/// with a single real lead and empty follow-up / call-log lists. Real data will
/// come from the backend once `ApiConfig.useMockData` is flipped off.

final mockLeads = <Lead>[
  Lead(
    id: 'lead-9063290012',
    name: '9063290012',
    phone: '9063290012',
    score: 0,
    temperature: LeadTemperature.warm,
    source: LeadSource.inbound,
    intent: '',
    lastContact: DateTime(2026, 6, 12),
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
  ),
];

final mockFollowUpTasks = <FollowUpTask>[];

final mockCallLog = <CallLogEntry>[];
