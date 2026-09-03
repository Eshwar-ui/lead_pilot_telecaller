import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lead.dart';
import '../state/providers.dart';
import 'call_recording_service.dart';

/// Resolves a phone number seen on the device's call log to the lead it
/// belongs to, or null when that number isn't one of this org's leads.
///
/// The null answer is the load-bearing one. `POST /api/calls/upload` CREATES a
/// lead for whatever phone number it is handed, so the auto-capture paths must
/// not reach it until a lead is known to exist — otherwise every personal call
/// on the telecaller's phone would quietly become a lead with a recording and
/// an AI analysis attached to it.
class LeadCallMatcher {
  const LeadCallMatcher(this._ref);

  final Ref _ref;

  Future<String?> matchLeadId(String phone) async {
    final local = matchInLeads(_ref.read(leadsProvider), phone);
    if (local != null) return local;

    // Not in this device's list — the lead may have been created on the web,
    // assigned to someone else, or simply not loaded yet. `/leads/dedupe` is
    // org-scoped and, unlike /upload, never creates a lead on a miss.
    try {
      final result = await _ref.read(leadRepositoryProvider).dedupe(phone);
      return result.duplicate ? result.contactKey : null;
    } catch (_) {
      // Offline or backend down: treat as "not a lead" for now. The next sweep
      // sees the same call-log entry again and retries.
      return null;
    }
  }

  /// The pure half, unit tested: last-10-digit match against an already-loaded
  /// lead list. Shares [CallRecordingService.phoneDigits] so a number matches
  /// a lead here exactly the way it matches a recording filename there.
  ///
  /// Numbers with fewer than 10 digits never match — short codes and service
  /// numbers would otherwise collide with each other.
  static String? matchInLeads(List<Lead> leads, String phone) {
    final digits = CallRecordingService.phoneDigits(phone);
    if (digits.length < 10) return null;
    for (final lead in leads) {
      if (CallRecordingService.phoneDigits(lead.phone) == digits) return lead.id;
    }
    return null;
  }
}

final leadCallMatcherProvider = Provider<LeadCallMatcher>(LeadCallMatcher.new);
