import '../models/lead.dart';

final mockLeads = <Lead>[
  Lead(
    id: 'ravi-kumar',
    name: 'Ravi Kumar',
    phone: '+91 98765 43210',
    score: 84,
    temperature: LeadTemperature.hot,
    source: LeadSource.meta,
    intent: 'High Intent',
    lastContact: DateTime(2026, 6, 7, 10, 15),
    totalCalls: 3,
    averageScore: 84,
    memory: const [
      MemoryInsight(
        text: 'Confirmed budget ₹80L-₹1Cr',
        callLabel: 'Call #2',
        colorKey: 'green',
      ),
      MemoryInsight(
        text: 'Worried about project completion timeline',
        callLabel: 'Call #2',
        colorKey: 'orange',
      ),
      MemoryInsight(
        text: "Wife's opinion needed before decision",
        callLabel: 'Call #2',
        colorKey: 'violet',
      ),
      MemoryInsight(
        text: 'Prefers Phase 2 over Phase 3 location',
        callLabel: 'Call #1',
        colorKey: 'violet',
      ),
    ],
    script: const AiScript(
      generatedAgo: 'Generated 11s ago',
      openingLine:
          '"Namaste Ravi-ji, this is Anita from Skyline Developers. Last time we spoke about the Phase 2 3BHK - wanted to share an update on the completion timeline you asked about."',
      keyPoints: [
        'Reconfirm budget - last quoted ₹80L-₹1Cr',
        'Share RERA timeline doc and Phase 1 handover evidence',
        'Propose Saturday site tour (note: wife should join)',
        "Don't pitch Phase 3 - he was firm on Phase 2",
      ],
      steps: [
        ScriptStep(
          title: 'Acknowledge RERA timeline concerns immediately',
          subtitle: "Opens trust. Don't skip this step.",
        ),
        ScriptStep(
          title: 'Propose site visit this weekend (Sat/Sun)',
          subtitle: 'Commitment = conversion trigger.',
        ),
        ScriptStep(
          title: 'Mention Phase 2 units within ₹95L budget',
          subtitle: 'Budget match removes #1 objection.',
        ),
      ],
    ),
    objections: const [
      Objection(
        question: '"Will it be ready on time?"',
        response:
            'Phase 1 was handed over 22 days ahead of RERA date. Phase 2 currently 4 weeks ahead of schedule.',
      ),
      Objection(
        question: '"Let me check with my wife"',
        response:
            "Offer joint site visit Saturday. Don't push for commitment without her.",
      ),
    ],
    checklist: const [
      ChecklistItem(
        id: 'budget',
        text: 'Confirm budget range (₹80L-₹1Cr)',
        completed: true,
      ),
      ChecklistItem(
        id: 'timeline',
        text: 'Address completion timeline concern',
        completed: true,
      ),
      ChecklistItem(
        id: 'visit',
        text: 'Offer site visit for Saturday',
        completed: false,
      ),
      ChecklistItem(
        id: 'wife-date',
        text: "Ask about wife's preferred move date",
        completed: false,
      ),
    ],
    history: const [
      CallRecord(
        title: 'Today, 10:15 AM',
        duration: Duration(minutes: 4, seconds: 12),
        score: 72,
      ),
      CallRecord(
        title: 'Yesterday, 11:20 AM',
        duration: Duration(minutes: 5, seconds: 8),
        score: 81,
      ),
    ],
  ),
  Lead(
    id: 'neha-reddy',
    name: 'Neha Reddy',
    phone: '+91 99887 76655',
    score: 72,
    temperature: LeadTemperature.warm,
    source: LeadSource.inbound,
    intent: 'Site Visit',
    lastContact: DateTime(2026, 6, 8, 16, 30),
    totalCalls: 2,
    averageScore: 72,
    memory: const [
      MemoryInsight(
        text: 'Asked for east-facing units',
        callLabel: 'Call #1',
        colorKey: 'green',
      ),
      MemoryInsight(
        text: 'Needs loan pre-approval help',
        callLabel: 'Call #1',
        colorKey: 'orange',
      ),
    ],
    script: const AiScript(
      generatedAgo: 'Generated 18s ago',
      openingLine:
          '"Hi Neha, this is Anita from Skyline. I checked the east-facing inventory you asked for and found two options that fit your budget."',
      keyPoints: [
        'Confirm loan status',
        'Share east-facing unit availability',
        'Offer Sunday morning visit',
      ],
      steps: [
        ScriptStep(
          title: 'Open with inventory update',
          subtitle: 'Makes the call specific.',
        ),
        ScriptStep(
          title: 'Ask about pre-approval',
          subtitle: 'Identifies financing risk.',
        ),
      ],
    ),
    objections: const [
      Objection(
        question: '"I need loan clarity"',
        response: 'Offer banker callback and EMI estimate.',
      ),
    ],
    checklist: const [
      ChecklistItem(
        id: 'inventory',
        text: 'Share east-facing inventory',
        completed: false,
      ),
      ChecklistItem(id: 'loan', text: 'Confirm loan status', completed: false),
    ],
    history: const [
      CallRecord(
        title: 'Yesterday, 4:30 PM',
        duration: Duration(minutes: 3, seconds: 44),
        score: 72,
      ),
    ],
  ),
];
