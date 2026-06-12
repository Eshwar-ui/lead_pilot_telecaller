import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api/api_config.dart';
import '../core/api/api_endpoints.dart';
import '../core/api/api_exception.dart';
import '../models/call_recording.dart';

/// One diarized speaker turn in a transcript.
class TranscriptEntry {
  const TranscriptEntry({
    required this.speakerId,
    required this.text,
    this.textEn,
    this.start,
    this.end,
  });

  final String speakerId;
  final String text;
  final String? textEn;
  final double? start;
  final double? end;

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) {
    double? toDouble(Object? v) => v is num ? v.toDouble() : null;
    return TranscriptEntry(
      speakerId: (json['speakerId'] ?? '0').toString(),
      text: (json['text'] ?? '').toString(),
      textEn: json['textEn']?.toString(),
      start: toDouble(json['start']),
      end: toDouble(json['end']),
    );
  }
}

/// LLM scores for the call (each 0–100).
class AnalysisScores {
  const AnalysisScores({
    required this.overall,
    required this.telecaller,
    required this.leadQuality,
    required this.sentiment,
  });

  final int overall;
  final int telecaller;
  final int leadQuality;
  final int sentiment;

  factory AnalysisScores.fromJson(Map<String, dynamic> json) {
    int toInt(Object? v) => v is num ? v.round() : 0;
    return AnalysisScores(
      overall: toInt(json['overall']),
      telecaller: toInt(json['telecaller']),
      leadQuality: toInt(json['leadQuality']),
      sentiment: toInt(json['sentiment']),
    );
  }
}

/// One row of the call score breakdown (score out of 20).
class AnalysisBreakdownItem {
  const AnalysisBreakdownItem({
    required this.label,
    required this.score,
    required this.note,
  });

  final String label;
  final int score; // 0–20
  final String note;

  double get progress => (score / 20).clamp(0, 1);
  bool get good => score >= 14; // ≥70%

  factory AnalysisBreakdownItem.fromJson(Map<String, dynamic> json) {
    return AnalysisBreakdownItem(
      label: (json['label'] ?? '').toString(),
      score: json['score'] is num ? (json['score'] as num).round() : 0,
      note: (json['note'] ?? '').toString(),
    );
  }
}

/// A suggested follow-up action.
class AnalysisNextStep {
  const AnalysisNextStep({required this.title, required this.action});

  final String title;
  final String action;

  factory AnalysisNextStep.fromJson(Map<String, dynamic> json) {
    return AnalysisNextStep(
      title: (json['title'] ?? '').toString(),
      action: (json['action'] ?? 'Note').toString(),
    );
  }
}

/// Structured analysis of the call (what the Score & Summary tabs render).
class CallAnalysis {
  const CallAnalysis({
    required this.summary,
    required this.keyPoints,
    required this.nextSteps,
    required this.scores,
    required this.breakdown,
    required this.sentimentNote,
    required this.followUpSuggestion,
  });

  final String summary;
  final List<String> keyPoints;
  final List<AnalysisNextStep> nextSteps;
  final AnalysisScores scores;
  final List<AnalysisBreakdownItem> breakdown;
  final String sentimentNote;
  final String followUpSuggestion;

  factory CallAnalysis.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) f) => [
      if (raw is List)
        for (final e in raw)
          if (e is Map<String, dynamic>) f(e),
    ];
    return CallAnalysis(
      summary: (json['summary'] ?? '').toString(),
      keyPoints: [
        if (json['keyPoints'] is List)
          for (final p in json['keyPoints'] as List)
            if (p != null) p.toString(),
      ],
      nextSteps: list(json['nextSteps'], AnalysisNextStep.fromJson),
      scores: AnalysisScores.fromJson(
        (json['scores'] as Map<String, dynamic>?) ?? const {},
      ),
      breakdown: list(json['breakdown'], AnalysisBreakdownItem.fromJson),
      sentimentNote: (json['sentimentNote'] ?? '').toString(),
      followUpSuggestion: (json['followUpSuggestion'] ?? '').toString(),
    );
  }
}

/// The text + diarization + analysis produced by the backend for a recording.
class CallTranscription {
  const CallTranscription({
    required this.transcript,
    required this.entries,
    this.language,
    this.transcriptEn,
    this.analysis,
  });

  final String transcript;
  final String? transcriptEn;
  final String? language;
  final List<TranscriptEntry> entries;
  final CallAnalysis? analysis;

  factory CallTranscription.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final entries = <TranscriptEntry>[
      if (rawEntries is List)
        for (final e in rawEntries)
          if (e is Map<String, dynamic>) TranscriptEntry.fromJson(e),
    ];
    final rawAnalysis = json['analysis'];
    return CallTranscription(
      transcript: (json['transcript'] ?? '').toString(),
      transcriptEn: json['transcriptEn']?.toString(),
      language: json['languageCode']?.toString(),
      entries: entries,
      analysis: rawAnalysis is Map<String, dynamic>
          ? CallAnalysis.fromJson(rawAnalysis)
          : null,
    );
  }
}

/// Uploads a captured [CallRecording] to the backend and waits for the
/// speech-to-text result.
///
/// The backend runs Sarvam's **batch** API (async), so this is a two-step
/// flow: `submit` returns a job id immediately, then we poll until the job is
/// `done` or `failed`. Sarvam (model + key + cost) lives entirely server-side.
///
/// Backend contract:
///   * `POST {baseUrl}/calls/transcribe` multipart (`audio`, `leadId`,
///     `recordedAt`) → `202 { jobId, status }`.
///   * `GET {baseUrl}/calls/transcribe/{jobId}` →
///     `{ status, languageCode, transcript, transcriptEn, entries[] }`.
class TranscriptionService {
  const TranscriptionService();

  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _pollTimeout = Duration(minutes: 5);

  /// Submits the recording then polls until the transcript is ready.
  Future<CallTranscription> transcribe({
    required CallRecording recording,
    required String leadId,
  }) async {
    final jobId = await _submit(recording: recording, leadId: leadId);
    return _pollUntilDone(jobId);
  }

  Future<String> _submit({
    required CallRecording recording,
    required String leadId,
  }) async {
    final file = recording.file;
    if (!file.existsSync()) {
      throw ApiException('Recording file no longer exists: ${recording.path}');
    }

    final uri = ApiConfig.uri(ApiEndpoints.transcribeCall);
    final request = http.MultipartRequest('POST', uri)
      ..fields['leadId'] = leadId
      ..fields['recordedAt'] = recording.recordedAt.toIso8601String()
      ..files.add(await http.MultipartFile.fromPath('audio', recording.path));

    request.headers.addAll(ApiConfig.defaultHeaders..remove('Content-Type'));

    http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(ApiConfig.timeout);
    } catch (e) {
      throw ApiException('Could not reach the transcription service.', cause: e);
    }

    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(
        'Could not start transcription (${streamed.statusCode}).',
        statusCode: streamed.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final jobId = decoded['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw const ApiException('Backend did not return a job id.');
      }
      return jobId;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Unexpected submit response.', cause: e);
    }
  }

  Future<CallTranscription> _pollUntilDone(String jobId) async {
    final deadline = DateTime.now().add(_pollTimeout);
    final uri = ApiConfig.uri(ApiEndpoints.transcribeJob(jobId));

    while (true) {
      await Future<void>.delayed(_pollInterval);

      http.Response res;
      try {
        res = await http
            .get(uri, headers: ApiConfig.defaultHeaders)
            .timeout(ApiConfig.timeout);
      } catch (e) {
        if (DateTime.now().isAfter(deadline)) {
          throw ApiException('Transcription timed out.', cause: e);
        }
        continue; // transient network hiccup — keep polling until the deadline
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          'Transcription status check failed (${res.statusCode}).',
          statusCode: res.statusCode,
        );
      }

      final Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        throw ApiException('Unexpected status response.', cause: e);
      }

      switch (decoded['status']?.toString()) {
        case 'done':
          return CallTranscription.fromJson(decoded);
        case 'failed':
          throw ApiException(
            decoded['error']?.toString() ?? 'Transcription failed.',
          );
        default:
          if (DateTime.now().isAfter(deadline)) {
            throw const ApiException(
              'Transcription is taking too long. Please try again.',
            );
          }
      }
    }
  }
}
