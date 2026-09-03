import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recording queued for (re)upload. Everything needed to retry the upload
/// later — after the app was offline, killed, or the network dropped — without
/// the original screen still being open.
class OutboxEntry {
  const OutboxEntry({
    required this.leadId,
    required this.path,
    this.name,
    this.phone,
    this.source,
    this.contactKey,
    this.callDateIso,
    this.captureSource,
    this.attempts = 0,
    this.lastError,
  });

  final String leadId;
  final String path;
  final String? name;
  final String? phone;
  final String? source;
  final String? contactKey;
  final String? callDateIso;

  /// How the recording was captured ("app_call", "auto_detected_backfill", …)
  /// — carried through the retry so a call detected outside the app is still
  /// labelled that way when the upload finally lands.
  final String? captureSource;

  final int attempts;
  final String? lastError;

  OutboxEntry copyWith({int? attempts, String? lastError}) => OutboxEntry(
        leadId: leadId,
        path: path,
        name: name,
        phone: phone,
        source: source,
        contactKey: contactKey,
        callDateIso: callDateIso,
        captureSource: captureSource,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'leadId': leadId,
        'path': path,
        'name': name,
        'phone': phone,
        'source': source,
        'contactKey': contactKey,
        'callDateIso': callDateIso,
        'captureSource': captureSource,
        'attempts': attempts,
        'lastError': lastError,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
        leadId: (j['leadId'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        source: j['source'] as String?,
        contactKey: j['contactKey'] as String?,
        callDateIso: j['callDateIso'] as String?,
        captureSource: j['captureSource'] as String?,
        attempts: j['attempts'] is num ? (j['attempts'] as num).toInt() : 0,
        lastError: j['lastError'] as String?,
      );
}

/// A durable queue of recordings whose upload hasn't succeeded yet.
///
/// This is the retry half of the upload story (the dedup ledger is the
/// don't-duplicate half): a failed upload is enqueued here and drained on the
/// next app resume, so a call recorded while offline isn't silently lost and
/// doesn't depend on the user re-opening the exact post-call screen. The queue
/// is keyed by file `path`, so re-enqueuing the same recording updates the
/// existing entry instead of duplicating it.
class LocalUploadOutbox {
  static const _key = 'upload_outbox_v1';
  static const _maxAttempts = 5;

  Future<List<OutboxEntry>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) OutboxEntry.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<OutboxEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  /// Add (or replace, keyed by path) a recording to retry later.
  Future<void> enqueue(OutboxEntry entry) async {
    final entries = (await all()).where((e) => e.path != entry.path).toList()
      ..add(entry);
    await _write(entries);
  }

  /// Remove a recording once its upload finally succeeded (or it's given up on).
  Future<void> remove(String path) async {
    final entries = (await all()).where((e) => e.path != path).toList();
    await _write(entries);
  }

  /// Record a failed retry: bumps the attempt count and drops the entry once it
  /// has exhausted [_maxAttempts] (so a permanently-bad file can't wedge the
  /// queue forever). Returns true if the entry is still queued afterwards.
  Future<bool> markFailure(String path, String error) async {
    final entries = await all();
    final out = <OutboxEntry>[];
    var stillQueued = false;
    for (final e in entries) {
      if (e.path != path) {
        out.add(e);
        continue;
      }
      final next = e.copyWith(attempts: e.attempts + 1, lastError: error);
      if (next.attempts < _maxAttempts) {
        out.add(next);
        stillQueued = true;
      }
      // else: exhausted -> dropped from the queue.
    }
    await _write(out);
    return stillQueued;
  }
}

final localUploadOutboxProvider = Provider<LocalUploadOutbox>(
  (_) => LocalUploadOutbox(),
);
