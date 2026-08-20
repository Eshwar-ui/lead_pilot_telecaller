import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/local_transcript_store.dart';
import 'package:lead_pilot_telecaller/src/services/transcription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists the backend call ID with a captured transcript', () async {
    final store = LocalTranscriptStore();
    await store.save(
      'lead-1',
      const CallTranscription(
        callId: 'call-123',
        transcript: 'Namaskaram',
        entries: [],
      ),
    );

    final restored = await store.load('lead-1');

    expect(restored?.callId, 'call-123');
    expect(restored?.transcript, 'Namaskaram');
  });
}
