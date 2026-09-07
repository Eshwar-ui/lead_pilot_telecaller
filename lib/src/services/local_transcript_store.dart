import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'local_database.dart';
import 'transcription_service.dart';

/// Persists per-lead call transcripts so they survive app restarts.
/// [callCaptureProvider] writes here after each successful transcription and
/// reads here on PostCallScreen open.
///
/// One SQLite row per lead. These were previously a SharedPreferences key
/// each, which is the worst case for that store: transcripts are large — full
/// text, a translation, per-turn entries, the analysis and its sentiment
/// timeline — and exactly one is ever wanted at a time, yet SharedPreferences
/// holds every key it has in memory for the life of the process. A telecaller
/// with a few hundred captured calls was carrying all of them to read one.
class LocalTranscriptStore {
  Future<void> save(String leadId, CallTranscription transcript) async {
    final db = await AppDatabase.instance.database;
    await db.insert('transcripts', {
      'lead_id': leadId,
      'data': jsonEncode(_toJson(transcript)),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CallTranscription?> load(String leadId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'transcripts',
      columns: const ['data'],
      where: 'lead_id = ?',
      whereArgs: [leadId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return CallTranscription.fromJson(
        jsonDecode(rows.first['data'] as String) as Map<String, dynamic>,
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
