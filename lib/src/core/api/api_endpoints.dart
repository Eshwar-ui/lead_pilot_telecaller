/// Single source of truth for backend endpoint paths.
///
/// Paths are relative to [ApiConfig.baseUrl] and mirror the FastAPI routes in
/// `voicesummary-main` (the "AI layer" backend). Keeping them here means a
/// backend route change is a one-line edit, not a codebase-wide search.
///
/// Route reference (FastAPI, port 8000):
///   * `/api/inbox`                          — lead inbox cards + header stats
///   * `/api/leads/{contact_key}`            — full lead detail (card+memory+calls)
///   * `/api/leads`                          — create lead (Save Lead)
///   * `/api/leads/dedupe?phone=`            — duplicate check
///   * `/api/leads/by-contact/{contact_key}/stage` — pipeline stage update
///   * `/api/memory/{contact_key}`           — memory bubble
///   * `/api/telecaller/score?window_days=`  — telecaller rolling score
///   * `/api/calls/upload`                   — outbound recording upload
///   * `/api/calls/{id}/processing-status`   — Upload→Transcribe→Analyse→Done
///   * `/api/calls/{id}/lead-analysis`       — per-call AI analysis
///   * `/api/calls/{id}/transcript/translate`— "View English" toggle
///   * `/api/attendance/check-in`            — clock in for today
///   * `/api/attendance/check-out`           — clock out for today
///   * `/api/attendance/today`                — today's attendance record
///   * `/api/auth/org`                        — org profile (name/logo/address/etc.)
class ApiEndpoints {
  const ApiEndpoints._();

  // Lead inbox + detail
  static const String inbox = '/api/inbox';
  static String leadDetail(String contactKey) => '/api/leads/$contactKey';
  static const String createLead = '/api/leads';
  static const String dedupeLead = '/api/leads/dedupe';

  // Pipeline stage update (mirrors the web Kanban's stage PATCH, but keyed by
  // contact_key since that's the only lead identifier the app ever sees).
  static String leadStage(String contactKey) =>
      '/api/leads/by-contact/$contactKey/stage';

  // Memory bubble (per-contact cumulative memory)
  static String memory(String contactKey) => '/api/memory/$contactKey';
  static String rebuildMemory(String contactKey) =>
      '/api/memory/$contactKey/rebuild';

  // Pre-Call brief (opening line/key points/script steps/objection
  // responses/checklist) — normally cached and returned inline by
  // [leadDetail]; this forces a fresh regeneration.
  static String rebuildPreCallBrief(String contactKey) =>
      '/api/leads/$contactKey/pre-call-brief/rebuild';

  // Telecaller score + trend
  static const String telecallerScore = '/api/telecaller/score';

  // Outbound recording upload → transcribe → analyse → memory
  static const String uploadRecording = '/api/calls/upload';
  static String processingStatus(String callId) =>
      '/api/calls/$callId/processing-status';

  // Per-call AI analysis
  static String leadAnalysis(String callId) =>
      '/api/calls/$callId/lead-analysis';

  // Consolidated Score-tab payload (rings + breakdown + sentiment timeline).
  // Requires a completed lead-analysis — the upload pipeline runs it automatically.
  static String callScore(String callId) => '/api/calls/$callId/score';

  // Raw transcript turns for a call
  static String transcript(String callId) => '/api/calls/$callId/transcript';

  // Transcript translation ("View English")
  static String translate(String callId) =>
      '/api/calls/$callId/transcript/translate';

  // Batch string translation ("View English" on the Summary/Score tabs) —
  // POST {"texts": [...], "target": "en"} -> {"texts": [...]}, index-aligned.
  static const String translateTexts = '/api/translate';

  // Attendance (clock in/out)
  static const String attendanceCheckIn = '/api/attendance/check-in';
  static const String attendanceCheckOut = '/api/attendance/check-out';
  static const String attendanceToday = '/api/attendance/today';
  static const String attendanceMine = '/api/attendance/mine';
  static String attendanceClose(String recordId) =>
      '/api/attendance/$recordId/close';

  // Follow-ups (previously local-only — SharedPreferences had no backend
  // counterpart, so a scheduled/completed follow-up was invisible to the
  // founder dashboard's missed-follow-up leakage metric).
  static const String followUps = '/api/follow-ups';
  static String followUp(String id) => '/api/follow-ups/$id';

  // Organization profile (Profile screen's org card)
  static const String orgProfile = '/api/auth/org';

  // Device call-log sync (every inbound/outbound/missed call, not just calls
  // placed through this app's own dialer button) — a sibling of /api/calls,
  // not nested under it, so it can't collide with calls.py's
  // GET /api/calls/{call_id} catch-all.
  static const String callLogSync = '/api/call-log/sync';
  static const String callLog = '/api/call-log';
}
