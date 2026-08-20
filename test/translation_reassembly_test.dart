import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/screens/call_detail_screen.dart';

// reassembleTranslatedSummary/reassembleTranslatedScore split a single flat
// translateTexts() response back into per-field translations by position —
// fragile to any length mismatch, flagged as untested in the earlier audit.
void main() {
  group('reassembleTranslatedSummary', () {
    test('splits key points and next-step texts back apart by position', () {
      final result = reassembleTranslatedSummary(
        keyPoints: ['point A', 'point B'],
        nextSteps: [
          {'text': 'call back'},
          {'title': 'send quote'},
        ],
        translated: [
          'pt A (EN)',
          'pt B (EN)',
          'call back (EN)',
          'send quote (EN)',
        ],
      );

      expect(result.keyPoints, ['pt A (EN)', 'pt B (EN)']);
      expect(result.nextSteps[0]['text'], 'call back (EN)');
      expect(result.nextSteps[1]['title'], 'send quote (EN)');
    });

    test('preserves whichever key (text vs title) the original step used', () {
      final result = reassembleTranslatedSummary(
        keyPoints: [],
        nextSteps: [
          {'title': 'follow up', 'other': 'unchanged'},
        ],
        translated: ['follow up (EN)'],
      );

      expect(result.nextSteps.single.containsKey('text'), isFalse);
      expect(result.nextSteps.single['title'], 'follow up (EN)');
      expect(result.nextSteps.single['other'], 'unchanged');
    });

    test('empty key points and empty next steps produce empty results', () {
      final result = reassembleTranslatedSummary(
        keyPoints: [],
        nextSteps: [],
        translated: [],
      );
      expect(result.keyPoints, isEmpty);
      expect(result.nextSteps, isEmpty);
    });

    test('only key points, no next steps', () {
      final result = reassembleTranslatedSummary(
        keyPoints: ['a', 'b', 'c'],
        nextSteps: [],
        translated: ['a-en', 'b-en', 'c-en'],
      );
      expect(result.keyPoints, ['a-en', 'b-en', 'c-en']);
      expect(result.nextSteps, isEmpty);
    });
  });

  group('reassembleTranslatedScore', () {
    test(
      'splits notes, relevance reason, and evidence back apart in order',
      () {
        final result = reassembleTranslatedScore(
          breakdown: [
            {'label': 'Rapport', 'note': 'Good rapport'},
            {'label': 'Objection', 'note': 'Handled well'},
          ],
          notes: ['Good rapport', 'Handled well'],
          relevanceReason: 'Matches ICP',
          evidenceLists: [
            [
              {'text': 'quote 1'},
            ],
            [
              {'text': 'quote 2'},
              {'text': 'quote 3'},
            ],
          ],
          translated: [
            'Good rapport (EN)',
            'Handled well (EN)',
            'Matches ICP (EN)',
            'quote 1 (EN)',
            'quote 2 (EN)',
            'quote 3 (EN)',
          ],
        );

        expect(result.relevanceReason, 'Matches ICP (EN)');
        expect(result.breakdown[0]['note'], 'Good rapport (EN)');
        expect(result.breakdown[1]['note'], 'Handled well (EN)');
        expect(result.breakdown[0]['evidence'][0]['text'], 'quote 1 (EN)');
        expect(result.breakdown[1]['evidence'][0]['text'], 'quote 2 (EN)');
        expect(result.breakdown[1]['evidence'][1]['text'], 'quote 3 (EN)');
      },
    );

    test(
      'an empty relevance reason is skipped entirely, not sent as a slot',
      () {
        final result = reassembleTranslatedScore(
          breakdown: [
            {'label': 'Rapport', 'note': 'Good'},
          ],
          notes: ['Good'],
          relevanceReason: '',
          evidenceLists: [[]],
          translated: ['Good (EN)'], // no relevance slot present
        );

        expect(result.relevanceReason, isNull);
        expect(result.breakdown.single['note'], 'Good (EN)');
        expect(result.breakdown.single['evidence'], isEmpty);
      },
    );

    test(
      'a dimension with no evidence quotes is handled without an index error',
      () {
        final result = reassembleTranslatedScore(
          breakdown: [
            {'label': 'A', 'note': 'note A'},
            {'label': 'B', 'note': 'note B'},
          ],
          notes: ['note A', 'note B'],
          relevanceReason: '',
          evidenceLists: [
            [], // dimension A has no evidence
            [
              {'text': 'only evidence'},
            ],
          ],
          translated: ['note A (EN)', 'note B (EN)', 'only evidence (EN)'],
        );

        expect(result.breakdown[0]['evidence'], isEmpty);
        expect(
          result.breakdown[1]['evidence'][0]['text'],
          'only evidence (EN)',
        );
      },
    );

    test(
      'empty breakdown produces an empty result with no relevance reason',
      () {
        final result = reassembleTranslatedScore(
          breakdown: [],
          notes: [],
          relevanceReason: '',
          evidenceLists: [],
          translated: [],
        );
        expect(result.breakdown, isEmpty);
        expect(result.relevanceReason, isNull);
      },
    );
  });
}
