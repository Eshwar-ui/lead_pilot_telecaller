import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_recording_service.dart';

/// What happened when we tried to put a lead in the phone's address book.
///
/// Every outcome is non-fatal by design: the lead itself is already saved on
/// the backend before this runs, so a denied permission or a flaky contacts
/// provider must never look like the lead failed to save.
enum ContactSaveOutcome {
  /// A new contact card was created.
  created,

  /// A contact already existed for this number; its name was refreshed.
  updated,

  /// Nothing to do — the existing contact already had this name.
  unchanged,

  /// The telecaller declined the contacts permission.
  permissionDenied,

  /// The number was too short to be a real, callable contact.
  invalidNumber,

  /// The contacts provider threw. Genuinely unexpected.
  failed,
}

extension ContactSaveOutcomeX on ContactSaveOutcome {
  /// Whether the telecaller should be told. Success is silent — they asked to
  /// save a lead, not to be congratulated about their address book.
  bool get isNoteworthy =>
      this == ContactSaveOutcome.permissionDenied ||
      this == ContactSaveOutcome.failed;

  String? get message => switch (this) {
    ContactSaveOutcome.permissionDenied =>
      "Lead saved. It wasn't added to your contacts — permission denied.",
    ContactSaveOutcome.failed =>
      "Lead saved, but it couldn't be added to your contacts.",
    _ => null,
  };
}

/// Writes leads into the phone's address book.
///
/// Why this exists: a lead saved in LeadPilot but absent from Contacts rings in
/// as an unknown number. Putting them in Contacts means the system dialer shows
/// the lead's NAME on an incoming call — which is also what makes the
/// auto-detected-call matching (see [LeadCallMatcher]) legible to the person
/// holding the phone, rather than a call log full of bare numbers.
class DeviceContactService {
  const DeviceContactService();

  /// Save (or refresh) the contact for a lead.
  ///
  /// Deduping is on the NORMALISED number via
  /// [CallRecordingService.phoneDigits] — the same last-10-digits rule the call
  /// matcher and the backend's `normalize_phone` use — so "+91 98765 43210",
  /// "098765 43210" and "9876543210" are one person and re-saving a lead
  /// updates a single card instead of spawning duplicates.
  ///
  /// Never throws. Callers save the lead FIRST and treat this as best effort.
  Future<ContactSaveOutcome> saveLead({
    required String name,
    required String phone,
  }) async {
    final digits = CallRecordingService.phoneDigits(phone);
    // Below 10 digits is a short code or a typo, not something a contact card
    // should exist for — the same floor the lead matcher applies.
    if (digits.length < 10 || name.trim().isEmpty) {
      return ContactSaveOutcome.invalidNumber;
    }

    try {
      // readonly: false — we intend to write. Requesting the read-only grant
      // first would force a SECOND prompt at the moment of writing.
      final granted = await FlutterContacts.requestPermission(readonly: false);
      if (!granted) return ContactSaveOutcome.permissionDenied;

      final existing = await _findByNumber(digits);
      final trimmedName = name.trim();

      if (existing != null) {
        if (existing.displayName.trim() == trimmedName) {
          return ContactSaveOutcome.unchanged;
        }
        // Only the name is touched. Overwriting anything else would clobber
        // details the telecaller may have added by hand on the phone.
        existing.name.first = trimmedName;
        existing.name.last = '';
        await existing.update();
        return ContactSaveOutcome.updated;
      }

      final contact = Contact()
        ..name.first = trimmedName
        ..phones = [Phone(phone.trim())];
      await contact.insert();
      return ContactSaveOutcome.created;
    } catch (_) {
      // A contacts provider that throws must not take the lead-save flow down
      // with it — the lead is already persisted server-side by this point.
      return ContactSaveOutcome.failed;
    }
  }

  /// The existing contact whose number normalises to [digits], or null.
  ///
  /// Fetches numbers only (no photos/emails) — the full-detail read is
  /// noticeably slower on a large address book and nothing here needs it.
  Future<Contact?> _findByNumber(String digits) async {
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );
    for (final c in contacts) {
      for (final p in c.phones) {
        if (CallRecordingService.phoneDigits(p.number) == digits) {
          // Re-fetch with properties so `update()` doesn't write back a
          // partially-populated record.
          return FlutterContacts.getContact(c.id);
        }
      }
    }
    return null;
  }
}

final deviceContactServiceProvider = Provider<DeviceContactService>(
  (ref) => const DeviceContactService(),
);
