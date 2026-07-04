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
///   * `/api/memory/{contact_key}`           — memory bubble
///   * `/api/telecaller/score?window_days=`  — telecaller rolling score
///   * `/api/calls/upload`                   — outbound recording upload
///   * `/api/calls/{id}/processing-status`   — Upload→Transcribe→Analyse→Done
///   * `/api/calls/{id}/lead-analysis`       — per-call AI analysis
///   * `/api/calls/{id}/transcript/translate`— "View English" toggle
///   * `/api/attendance/check-in`            — clock in for today
///   * `/api/attendance/check-out`           — clock out for today
///   * `/api/attendance/today`                — today's attendance record
class ApiEndpoints {
  const ApiEndpoints._();

  // Lead inbox + detail
  static const String inbox = '/api/inbox';
  static String leadDetail(String contactKey) => '/api/leads/$contactKey';
  static const String createLead = '/api/leads';
  static const String dedupeLead = '/api/leads/dedupe';

  // Memory bubble (per-contact cumulative memory)
  static String memory(String contactKey) => '/api/memory/$contactKey';
  static String rebuildMemory(String contactKey) =>
      '/api/memory/$contactKey/rebuild';

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

  // Attendance (clock in/out)
  static const String attendanceCheckIn = '/api/attendance/check-in';
  static const String attendanceCheckOut = '/api/attendance/check-out';
  static const String attendanceToday = '/api/attendance/today';
}
