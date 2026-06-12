/// Single source of truth for backend endpoint paths.
///
/// Paths are relative to [ApiConfig.baseUrl]. Keeping them here means a backend
/// route change is a one-line edit, not a codebase-wide search.
class ApiEndpoints {
  const ApiEndpoints._();

  // Leads
  static const String leads = '/leads';
  static String leadById(String id) => '/leads/$id';
  static const String outboundLeads = '/leads/outbound';

  // Follow-ups
  static const String followUps = '/follow-ups';
  static String followUpById(String id) => '/follow-ups/$id';

  // Call logs
  static const String callLogs = '/call-logs';

  // Call-recording speech-to-text (multipart audio upload → async job)
  static const String transcribeCall = '/calls/transcribe';
  static String transcribeJob(String jobId) => '/calls/transcribe/$jobId';

  // Per-lead call notes
  static String leadNotes(String leadId) => '/leads/$leadId/notes';

  // Per-lead pre-call checklist
  static String leadChecklist(String leadId) => '/leads/$leadId/checklist';
}
