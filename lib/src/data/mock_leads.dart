import '../models/lead.dart';

final mockFollowUpTasks = <FollowUpTask>[
  const FollowUpTask(
    id: 'task-1',
    taskText: 'Send EMI sheet (WhatsApp)',
    leadName: 'Ravi Kumar',
    leadId: 'ravi-kumar',
    phone: '+91 87654 32109',
    status: FollowUpStatus.overdue,
    dueLabel: 'Due 11:30 AM',
    dueToday: true,
  ),
  const FollowUpTask(
    id: 'task-2',
    taskText: 'Send brochure',
    leadName: 'Sneha Reddy',
    leadId: 'neha-reddy',
    phone: '+91 99887 76655',
    status: FollowUpStatus.pending,
    dueLabel: 'Today, 6:00 PM',
    dueToday: true,
  ),
  const FollowUpTask(
    id: 'task-3',
    taskText: 'Schedule Site Visit',
    leadName: 'Sneha Reddy',
    leadId: 'neha-reddy',
    status: FollowUpStatus.pending,
    dueLabel: 'Today',
    dueToday: true,
  ),
  const FollowUpTask(
    id: 'task-4',
    taskText: 'Call back',
    leadName: 'Arjun Desai',
    phone: '+91 65432 10987',
    status: FollowUpStatus.pending,
    dueLabel: 'Tomorrow, 10:00 AM',
    dueToday: false,
  ),
  const FollowUpTask(
    id: 'task-5',
    taskText: 'Email site plan',
    leadName: 'Meera Krishnan',
    phone: '+91 76543 21098',
    status: FollowUpStatus.pending,
    dueLabel: 'Fri, 11:00 AM',
    dueToday: false,
  ),
];

final mockCallLog = <CallLogEntry>[
  CallLogEntry(
    id: 'log-1',
    leadName: 'Sneha Reddy',
    phone: '+91 99887 76655',
    intent: 'High Intent',
    source: LeadSource.inbound,
    duration: Duration(minutes: 6, seconds: 22),
    score: 92,
    calledAt: DateTime(2026, 6, 9, 11, 48),
    isInbound: true,
  ),
  CallLogEntry(
    id: 'log-2',
    leadName: 'Ravi Kumar',
    phone: '+91 87654 32109',
    intent: 'High Intent',
    source: LeadSource.meta,
    duration: Duration(minutes: 5, seconds: 8),
    score: 84,
    calledAt: DateTime(2026, 6, 9, 10, 15),
  ),
  CallLogEntry(
    id: 'log-3',
    leadName: 'Arjun Desai',
    phone: '+91 65432 10987',
    intent: 'High Intent',
    source: LeadSource.referral,
    duration: Duration(minutes: 5, seconds: 8),
    score: 88,
    calledAt: DateTime(2026, 6, 8, 16, 30),
  ),
  CallLogEntry(
    id: 'log-4',
    leadName: 'Meera Krishnan',
    phone: '+91 76543 21098',
    intent: 'Warm',
    source: LeadSource.website,
    duration: Duration(minutes: 7, seconds: 55),
    score: 81,
    calledAt: DateTime(2026, 6, 8, 13, 2),
  ),
  CallLogEntry(
    id: 'log-5',
    leadName: 'Ravi Verma',
    phone: '+91 98765 43210',
    intent: 'New',
    source: LeadSource.event,
    duration: Duration(minutes: 1, seconds: 36),
    score: 72,
    calledAt: DateTime(2026, 6, 7, 11, 20),
  ),
  CallLogEntry(
    id: 'log-6',
    leadName: 'Meera Krishnan',
    phone: '+91 76543 21098',
    intent: 'Warm',
    source: LeadSource.website,
    duration: Duration(minutes: 4, seconds: 12),
    score: 75,
    calledAt: DateTime(2026, 6, 7, 10, 0),
  ),
];

final mockLeads = <Lead>[
  Lead(
    id: 'ravi-kumar',
    name: 'Ravi Kumar',
    phone: '+91 98765 43210',
    score: 84,
    temperature: LeadTemperature.hot,
    source: LeadSource.inbound,
    intent: 'High Intent',
    lastContact: DateTime(2026, 6, 9, 6, 15),
    propertyInterest: 'Luxury Villas Search',
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
    score: 92,
    temperature: LeadTemperature.hot,
    source: LeadSource.inbound,
    intent: 'High Intent',
    lastContact: DateTime(2026, 6, 9, 6, 30),
    propertyInterest: 'Luxury Villas Search',
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
  Lead(
    id: 'arjun-desai',
    name: 'Arjun Desai',
    phone: '+91 76543 21098',
    score: 45,
    temperature: LeadTemperature.cold,
    source: LeadSource.organic,
    intent: '',
    lastContact: DateTime(2026, 6, 8, 10, 0),
    totalCalls: 1,
    averageScore: 45,
    propertyInterest: 'Direct Traffic',
    memory: const [],
    script: const AiScript(
      generatedAgo: 'Generated 2m ago',
      openingLine:
          '"Hi Arjun, this is Anita from Skyline. I wanted to follow up on your inquiry."',
      keyPoints: [
        'Understand budget range',
        'Identify preferred location',
        'Propose a site visit',
      ],
      steps: [
        ScriptStep(
          title: 'Open with their inquiry',
          subtitle: 'Build rapport first.',
        ),
      ],
    ),
    objections: const [],
    checklist: const [
      ChecklistItem(id: 'budget', text: 'Confirm budget', completed: false),
    ],
    history: const [
      CallRecord(
        title: 'Yesterday, 9:00 AM',
        duration: Duration(minutes: 2, seconds: 15),
        score: 45,
      ),
    ],
  ),
  Lead(
    id: 'meera-krishnan',
    name: 'Meera Krishnan',
    phone: '+91 65432 10987',
    score: 31,
    temperature: LeadTemperature.cold,
    source: LeadSource.meta,
    intent: '',
    lastContact: DateTime(2026, 6, 8, 9, 0),
    totalCalls: 1,
    averageScore: 31,
    propertyInterest: 'Commercial Plots',
    memory: const [],
    script: const AiScript(
      generatedAgo: 'Generated 5m ago',
      openingLine:
          '"Hi Meera, this is Anita from Skyline. I saw your inquiry about commercial plots."',
      keyPoints: [
        'Understand commercial purpose',
        'Budget and timeline',
        'Preferred area',
      ],
      steps: [
        ScriptStep(
          title: 'Ask about commercial purpose',
          subtitle: 'Investment vs self-use.',
        ),
      ],
    ),
    objections: const [],
    checklist: const [
      ChecklistItem(id: 'needs', text: 'Understand property needs', completed: false),
    ],
    history: const [
      CallRecord(
        title: 'Yesterday, 10:00 AM',
        duration: Duration(minutes: 1, seconds: 44),
        score: 31,
      ),
    ],
  ),
];
