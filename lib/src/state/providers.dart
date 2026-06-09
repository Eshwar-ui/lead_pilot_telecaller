import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_leads.dart';
import '../models/lead.dart';

final leadsProvider = Provider<List<Lead>>((ref) => mockLeads);
final followUpsProvider = Provider<List<FollowUpTask>>((ref) => mockFollowUpTasks);
final callLogProvider = Provider<List<CallLogEntry>>((ref) => mockCallLog);

final selectedLeadIdProvider =
    NotifierProvider<SelectedLeadIdController, String>(
      SelectedLeadIdController.new,
    );

class SelectedLeadIdController extends Notifier<String> {
  @override
  String build() => mockLeads.first.id;

  void set(String value) => state = value;
}

final selectedLeadProvider = Provider<Lead>((ref) {
  final leads = ref.watch(leadsProvider);
  final id = ref.watch(selectedLeadIdProvider);
  return leads.firstWhere((lead) => lead.id == id, orElse: () => leads.first);
});

final checklistProvider =
    NotifierProvider<ChecklistController, Map<String, Set<String>>>(
      ChecklistController.new,
    );

class ChecklistController extends Notifier<Map<String, Set<String>>> {
  @override
  Map<String, Set<String>> build() {
    return {
      for (final lead in mockLeads)
        lead.id: lead.checklist
            .where((item) => item.completed)
            .map((item) => item.id)
            .toSet(),
    };
  }

  void toggle(String leadId, String itemId) {
    final current = {...state};
    final selected = {...(current[leadId] ?? <String>{})};
    selected.contains(itemId) ? selected.remove(itemId) : selected.add(itemId);
    current[leadId] = selected;
    state = current;
  }
}

enum CallerChoice { phone, trueCaller, others }

final callerChoiceProvider =
    NotifierProvider<CallerChoiceController, CallerChoice?>(
      CallerChoiceController.new,
    );
final rememberCallerChoiceProvider =
    NotifierProvider<RememberCallerChoiceController, bool>(
      RememberCallerChoiceController.new,
    );

class CallerChoiceController extends Notifier<CallerChoice?> {
  @override
  CallerChoice? build() => null;

  void set(CallerChoice value) => state = value;
}

class RememberCallerChoiceController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final outboundLeadDraftProvider =
    NotifierProvider<OutboundLeadDraftController, OutboundLeadDraft>(
      OutboundLeadDraftController.new,
    );

class OutboundLeadDraftController extends Notifier<OutboundLeadDraft> {
  @override
  OutboundLeadDraft build() => const OutboundLeadDraft();

  void updateName(String value) => state = state.copyWith(name: value);
  void updatePhone(String value) => state = state.copyWith(phone: value);
  void updateReason(String value) => state = state.copyWith(reason: value);
  void updateSource(String value) => state = state.copyWith(source: value);
}
