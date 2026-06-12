import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SarvamAIClient } from 'sarvamai';
import { promises as fs } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { randomUUID } from 'crypto';

export interface DiarizedEntry {
  speakerId: string;
  text: string;
  start: number | null;
  end: number | null;
}

export interface DiarizedResult {
  languageCode: string | null;
  transcript: string;
  entries: DiarizedEntry[];
}

/// Thin wrapper over the official `sarvamai` SDK for the two calls we need:
/// batch speech-to-text with diarization, and text translation to English.
@Injectable()
export class SarvamService {
  private readonly logger = new Logger(SarvamService.name);
  private readonly client: SarvamAIClient;
  private readonly chatModel: string;

  constructor(config: ConfigService) {
    const key = config.get<string>('SARVAM_API_KEY');
    if (!key) {
      throw new Error('SARVAM_API_KEY is not set (see server/.env.example).');
    }
    this.client = new SarvamAIClient({ apiSubscriptionKey: key });
    // sarvam-m (legacy 24B) by default; bump to sarvam-30b/105b via env for
    // stronger structured-JSON output.
    this.chatModel = config.get<string>('SARVAM_CHAT_MODEL') ?? 'sarvam-m';
  }

  /// Single-shot chat completion (system + user) returning the text content.
  async chat(systemPrompt: string, userPrompt: string): Promise<string> {
    const res = (await this.client.chat.completions({
      model: this.chatModel as never,
      temperature: 0.2,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
    })) as unknown as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    return res.choices?.[0]?.message?.content ?? '';
  }

  /// Runs a Sarvam batch STT job (saaras:v3, diarized) over a single audio file
  /// and returns the diarized transcript in the original language.
  async transcribeDiarized(filePath: string): Promise<DiarizedResult> {
    const job = await this.client.speechToTextJob.createJob({
      model: 'saaras:v3',
      mode: 'transcribe',
      languageCode: 'unknown', // auto-detect Hindi/Hinglish/regional
      withDiarization: true,
      withTimestamps: true,
      numSpeakers: 2,
    });

    this.logger.log(`Sarvam job ${job.jobId}: uploading…`);
    await job.uploadFiles([filePath]);
    await job.start();
    // Poll every 5s, allow up to 30 min for long calls.
    await job.waitUntilComplete(5, 1800);

    const outDir = join(tmpdir(), `leadpilot-out-${randomUUID()}`);
    await fs.mkdir(outDir, { recursive: true });
    try {
      await job.downloadOutputs(outDir);
      const files = await fs.readdir(outDir);
      const jsonFile = files.find((f) => f.endsWith('.json'));
      if (!jsonFile) {
        throw new Error('Sarvam job produced no JSON output.');
      }
      const raw = await fs.readFile(join(outDir, jsonFile), 'utf-8');
      return this.parseOutput(raw);
    } finally {
      await fs.rm(outDir, { recursive: true, force: true }).catch(
        () => undefined,
      );
    }
  }

  /// Translates a single chunk of text to English. Source language auto-detected.
  async translateToEnglish(text: string): Promise<string> {
    const res = await this.client.text.translate({
      input: text,
      source_language_code: 'auto',
      target_language_code: 'en-IN',
    });
    return res.translated_text ?? '';
  }

  private parseOutput(raw: string): DiarizedResult {
    const data = JSON.parse(raw) as {
      transcript?: string;
      language_code?: string;
      diarized_transcript?: {
        entries?: Array<{
          transcript?: string;
          speaker_id?: string | number;
          start_time_seconds?: number;
          end_time_seconds?: number;
        }>;
      };
    };

    const languageCode = data.language_code ?? null;
    const transcript = data.transcript ?? '';
    const entries: DiarizedEntry[] = [];

    const diarized = data.diarized_transcript?.entries;
    if (Array.isArray(diarized) && diarized.length > 0) {
      for (const e of diarized) {
        const text = (e.transcript ?? '').trim();
        if (!text) continue;
        entries.push({
          speakerId: String(e.speaker_id ?? '0'),
          text,
          start:
            typeof e.start_time_seconds === 'number'
              ? e.start_time_seconds
              : null,
          end:
            typeof e.end_time_seconds === 'number' ? e.end_time_seconds : null,
        });
      }
    }

    // No diarization in output (or empty) — fall back to a single block.
    if (entries.length === 0 && transcript.trim()) {
      entries.push({
        speakerId: '0',
        text: transcript.trim(),
        start: null,
        end: null,
      });
    }

    return { languageCode, transcript, entries };
  }
}
