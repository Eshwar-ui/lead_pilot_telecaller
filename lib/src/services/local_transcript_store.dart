import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transcription_service.dart';

/// Persists per-lead call transcripts to device storage so they survive app
/// restarts. [callCaptureProvider] writes here after each successful
/// transcription and reads here on PostCallScreen open.
class LocalTranscriptStore {
  static const _prefix = 'transcript_v1_';

  Future<void> save(String leadId, CallTranscription transcript) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$leadId', jsonEncode(_toJson(transcript)));
  }

  Future<CallTranscription?> load(String leadId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$leadId');
    if (raw == null) return null;
    try {
      return CallTranscription.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _toJson(CallTranscription t) => {
    'transcript': t.transcript,
    if (t.callId != null) 'callId': t.callId,
    if (t.transcriptEn != null) 'transcriptEn': t.transcriptEn,
    if (t.language != null) 'languageCode': t.language,
    'entries': [
      for (final e in t.entries)
        {
          'speakerId': e.speakerId,
          'text': e.text,
          if (e.textEn != null) 'textEn': e.textEn,
          if (e.start != null) 'start': e.start,
          if (e.end != null) 'end': e.end,
        },
    ],
    if (t.analysis != null) 'analysis': _analysisJson(t.analysis!),
  };

  Map<String, dynamic> _analysisJson(CallAnalysis a) => {
    'summary': a.summary,
    'keyPoints': a.keyPoints,
    'nextSteps': [
      for (final s in a.nextSteps) {'title': s.title, 'action': s.action},
    ],
    'scores': {
      'overall': a.scores.overall,
      'telecaller': a.scores.telecaller,
      'leadQuality': a.scores.leadQuality,
      'sentiment': a.scores.sentiment,
    },
    'breakdown': [
      for (final b in a.breakdown)
        {'label': b.label, 'score': b.score, 'note': b.note},
    ],
    'sentimentNote': a.sentimentNote,
    'followUpSuggestion': a.followUpSuggestion,
    'sentimentTimeline': [for (final s in a.sentimentTimeline) s.toJson()],
  };
}

final localTranscriptStoreProvider = Provider<LocalTranscriptStore>(
  (_) => LocalTranscriptStore(),
);
