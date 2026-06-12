/// One speaker turn in a diarized transcript.
export interface TranscriptEntryDto {
  speakerId: string;
  text: string;
  textEn: string | null;
  start: number | null;
  end: number | null;
}

/// Returned by POST /calls/transcribe (submit) and GET /calls/transcribe/:id (poll).
export interface TranscribeResponseDto {
  jobId: string;
  status: 'processing' | 'done' | 'failed';
  languageCode?: string | null;
  transcript?: string | null;
  transcriptEn?: string | null;
  entries?: TranscriptEntryDto[];
  /// LLM scoring/summary (null until analysis completes). Shape mirrors
  /// AnalysisService.CallAnalysis.
  analysis?: unknown;
  error?: string | null;
}
