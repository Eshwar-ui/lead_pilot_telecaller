import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';

// Regression cover for the pipeline-stage picker's guardrail: reversing a
// terminal decision (Lost/Junk -> Won, or Won -> Lost/Junk) used to be
// misclassified as a no-note "forward" move — a Junk lead could be silently
// flipped straight to Closed Won, or a real Closed Won deal silently
// discarded, with no note and no audit trail. Fixed in
// computeStagePickerOptions (extracted from LeadDetailScreen's _openPicker
// so this matrix can be tested directly, without a widget pump).
void main() {
  // Mirrors _PipelineStrip._working in lead_detail_screen.dart.
  const working = [
    LeadStage.newLead,
    LeadStage.assigned,
    LeadStage.contacted,
    LeadStage.interested,
    LeadStage.proposalSent,
    LeadStage.negotiation,
  ];

  group('computeStagePickerOptions — ordinary working-pipeline stage', () {
    test('mid-pipeline stage can advance forward without a note', () {
      final options = computeStagePickerOptions(LeadStage.contacted, working);
      expect(
        options.forward,
        containsAll([LeadStage.interested, LeadStage.proposalSent]),
      );
      expect(options.forward, contains(LeadStage.closedWon));
      expect(options.canCloseWithoutNote, isTrue);
    });

    test('earlier working stages require a note to move back to', () {
      final options = computeStagePickerOptions(LeadStage.negotiation, working);
      expect(
        options.backward,
        containsAll([
          LeadStage.newLead,
          LeadStage.assigned,
          LeadStage.contacted,
        ]),
      );
      expect(options.forward, isNot(contains(LeadStage.assigned)));
    });

    test(
      'Closed Lost/Junk are reachable without a note from a working stage',
      () {
        final options = computeStagePickerOptions(
          LeadStage.proposalSent,
          working,
        );
        expect(options.canCloseWithoutNote, isTrue);
      },
    );
  });

  group('computeStagePickerOptions — terminal-decision reversal requires a note', () {
    test('Junk -> Closed Won requires a note (not a no-note forward move)', () {
      final options = computeStagePickerOptions(LeadStage.junk, working);
      expect(
        options.forward,
        isNot(contains(LeadStage.closedWon)),
        reason:
            'reopening a Junk lead straight to Won must not be a one-tap no-note move',
      );
      expect(options.backward, contains(LeadStage.closedWon));
    });

    test('Closed Lost -> Closed Won requires a note', () {
      final options = computeStagePickerOptions(LeadStage.closedLost, working);
      expect(options.forward, isNot(contains(LeadStage.closedWon)));
      expect(options.backward, contains(LeadStage.closedWon));
    });

    test(
      'Closed Won -> Closed Lost/Junk requires a note, not the quick-close buttons',
      () {
        final options = computeStagePickerOptions(LeadStage.closedWon, working);
        expect(
          options.canCloseWithoutNote,
          isFalse,
          reason: 'discarding a won deal must not be a one-tap no-note move',
        );
        expect(
          options.backward,
          containsAll([LeadStage.closedLost, LeadStage.junk]),
        );
      },
    );

    test(
      'a terminal-negative lead cannot no-note re-close (Junk -> Lost is unreachable, '
      'not offered as a quick-close option)',
      () {
        final options = computeStagePickerOptions(LeadStage.junk, working);
        expect(options.canCloseWithoutNote, isFalse);
      },
    );
  });

  group(
    'computeStagePickerOptions — Closed Won reopening into the working pipeline',
    () {
      test(
        'Closed Won can still reopen back into a working stage, with a note',
        () {
          final options = computeStagePickerOptions(
            LeadStage.closedWon,
            working,
          );
          expect(options.backward, contains(LeadStage.negotiation));
        },
      );

      test('Closed Won has no no-note forward options left', () {
        final options = computeStagePickerOptions(LeadStage.closedWon, working);
        expect(options.forward, isEmpty);
      });
    },
  );
}
