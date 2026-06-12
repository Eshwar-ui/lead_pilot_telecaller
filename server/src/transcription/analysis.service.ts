import { Injectable, Logger } from '@nestjs/common';
import { SarvamService } from './sarvam.service';
import { DiarizedEntry } from './sarvam.service';

export interface AnalysisScores {
  overall: number; // 0–100
  telecaller: number; // 0–100
  leadQuality: number; // 0–100
  sentiment: number; // 0–100
}

export interface AnalysisBreakdownItem {
  label: string; // Opening | Discovery | Pitch | Objection Handling | Closing
  score: number; // 0–20
  note: string;
}

export interface AnalysisNextStep {
  title: string;
  action: string; // short button label, e.g. "Send now" | "Schedule" | "Note"
}

export interface CallAnalysis {
  summary: string;
  keyPoints: string[];
  nextSteps: AnalysisNextStep[];
  scores: AnalysisScores;
  breakdown: AnalysisBreakdownItem[];
  sentimentNote: string;
  followUpSuggestion: string;
}

const SYSTEM_PROMPT = `You are a sales-call quality analyst for a real-estate telecaller team in India.
You receive a diarized transcript of an outbound call where "You" is the telecaller (agent) and the other speaker is the lead (prospect). The transcript may be in Hindi, Hinglish, or a regional language.

Analyse the call and respond with ONLY a single JSON object (no markdown, no prose, no code fences) in English, with EXACTLY this shape:
{
  "summary": "2-3 sentence plain-English summary of the call",
  "keyPoints": ["3 to 6 short bullet strings of what the lead said/wants"],
  "nextSteps": [{"title": "short action", "action": "Send now"}],
  "scores": {"overall": 0-100, "telecaller": 0-100, "leadQuality": 0-100, "sentiment": 0-100},
  "breakdown": [
    {"label": "Opening", "score": 0-20, "note": "one sentence"},
    {"label": "Discovery", "score": 0-20, "note": "one sentence"},
    {"label": "Pitch", "score": 0-20, "note": "one sentence"},
    {"label": "Objection Handling", "score": 0-20, "note": "one sentence"},
    {"label": "Closing", "score": 0-20, "note": "one sentence"}
  ],
  "sentimentNote": "one sentence on the lead's sentiment over the call",
  "followUpSuggestion": "one sentence suggesting the next follow-up"
}
Rules: scores are integers. "overall" should roughly reflect the breakdown total. "action" must be 1-2 words. Keep all strings concise. Output the JSON object only.`;

/// Turns a diarized transcript into the structured scoring/summary the
/// Score and Summary tabs render. Uses Sarvam chat (Sarvam-M by default).
@Injectable()
export class AnalysisService {
  private readonly logger = new Logger(AnalysisService.name);

  constructor(private readonly sarvam: SarvamService) {}

  async analyze(
    entries: DiarizedEntry[],
    fallbackTranscript: string,
  ): Promise<CallAnalysis | null> {
    const transcriptText = this.formatTranscript(entries, fallbackTranscript);
    if (!transcriptText.trim()) return null;

    let content: string;
    try {
      content = await this.sarvam.chat(
        SYSTEM_PROMPT,
        `Transcript:\n${transcriptText}`,
      );
    } catch (err) {
      const m = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Analysis chat failed: ${m}`);
      return null;
    }

    const parsed = this.parseJson(content);
    if (!parsed) {
      this.logger.warn('Analysis response was not valid JSON.');
      return null;
    }
    return this.normalize(parsed);
  }

  /// "You" for the first speaker (telecaller), "Lead" otherwise.
  private formatTranscript(
    entries: DiarizedEntry[],
    fallback: string,
  ): string {
    if (!entries.length) return fallback;
    const first = entries[0].speakerId;
    return entries
      .map((e) => `${e.speakerId === first ? 'You' : 'Lead'}: ${e.text}`)
      .join('\n');
  }

  private parseJson(raw: string): Record<string, unknown> | null {
    if (!raw) return null;
    // Strip code fences and isolate the first {...} block.
    const fenced = raw.replace(/```(?:json)?/gi, '').trim();
    const start = fenced.indexOf('{');
    const end = fenced.lastIndexOf('}');
    if (start === -1 || end === -1 || end <= start) return null;
    try {
      return JSON.parse(fenced.slice(start, end + 1)) as Record<
        string,
        unknown
      >;
    } catch {
      return null;
    }
  }

  /// Defensive normalisation — coerce/clamp into the shape the app expects, so
  /// a slightly-off model response still renders.
  private normalize(data: Record<string, unknown>): CallAnalysis {
    const clamp = (v: unknown, max: number): number => {
      const n = typeof v === 'number' ? v : Number(v);
      if (!Number.isFinite(n)) return 0;
      return Math.max(0, Math.min(max, Math.round(n)));
    };
    const str = (v: unknown): string => (v == null ? '' : String(v));
    const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);

    const scores = (data.scores ?? {}) as Record<string, unknown>;

    const labels = [
      'Opening',
      'Discovery',
      'Pitch',
      'Objection Handling',
      'Closing',
    ];
    const rawBreakdown = arr(data.breakdown) as Record<string, unknown>[];
    const breakdown: AnalysisBreakdownItem[] = labels.map((label) => {
      const match = rawBreakdown.find(
        (b) => str(b.label).toLowerCase() === label.toLowerCase(),
      );
      return {
        label,
        score: clamp(match?.score, 20),
        note: str(match?.note),
      };
    });

    return {
      summary: str(data.summary),
      keyPoints: arr(data.keyPoints).map(str).filter(Boolean),
      nextSteps: arr(data.nextSteps).map((s) => {
        const o = (s ?? {}) as Record<string, unknown>;
        return { title: str(o.title), action: str(o.action) || 'Note' };
      }),
      scores: {
        overall: clamp(scores.overall, 100),
        telecaller: clamp(scores.telecaller, 100),
        leadQuality: clamp(scores.leadQuality, 100),
        sentiment: clamp(scores.sentiment, 100),
      },
      breakdown,
      sentimentNote: str(data.sentimentNote),
      followUpSuggestion: str(data.followUpSuggestion),
    };
  }
}
