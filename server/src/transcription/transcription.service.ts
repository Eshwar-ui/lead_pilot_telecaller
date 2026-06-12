import { Injectable, Logger } from '@nestjs/common';
import { promises as fs } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { SarvamService } from './sarvam.service';
import { AnalysisService } from './analysis.service';
import {
  TranscribeResponseDto,
  TranscriptEntryDto,
} from './dto/transcribe-response.dto';

interface SubmitInput {
  buffer: Buffer;
  originalName: string;
  leadId: string;
  recordedAt?: string;
}

@Injectable()
export class TranscriptionService {
  private readonly logger = new Logger(TranscriptionService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly sarvam: SarvamService,
    private readonly analysis: AnalysisService,
  ) {}

  /// Persist a `processing` row, fire off the (async) Sarvam pipeline without
  /// blocking the request, and return the job id for the client to poll.
  async submit(input: SubmitInput): Promise<TranscribeResponseDto> {
    const row = await this.prisma.callTranscript.create({
      data: {
        leadId: input.leadId,
        status: 'processing',
        recordedAt: input.recordedAt ? new Date(input.recordedAt) : null,
      },
    });

    // Fire-and-forget: the request returns now; processing continues in the
    // background. Errors are caught and written to the row.
    void this.process(row.id, input.buffer, input.originalName);

    return { jobId: row.id, status: 'processing' };
  }

  async get(id: string): Promise<TranscribeResponseDto | null> {
    const row = await this.prisma.callTranscript.findUnique({ where: { id } });
    if (!row) return null;
    return {
      jobId: row.id,
      status: row.status as TranscribeResponseDto['status'],
      languageCode: row.languageCode,
      transcript: row.transcript,
      transcriptEn: row.transcriptEn,
      entries: (row.entries as unknown as TranscriptEntryDto[]) ?? undefined,
      analysis: row.analysis ?? undefined,
      error: row.error,
    };
  }

  /// The actual work: write a temp file, run Sarvam batch STT + diarization,
  /// translate each turn to English, persist, then delete the audio.
  private async process(
    id: string,
    buffer: Buffer,
    originalName: string,
  ): Promise<void> {
    const ext = originalName.includes('.')
      ? originalName.slice(originalName.lastIndexOf('.'))
      : '.mp3';
    const tempPath = join(tmpdir(), `leadpilot-${randomUUID()}${ext}`);

    try {
      await fs.writeFile(tempPath, buffer);

      const result = await this.sarvam.transcribeDiarized(tempPath);

      // Translate each diarized turn to English (cache identical strings).
      const cache = new Map<string, string>();
      const entries: TranscriptEntryDto[] = [];
      for (const e of result.entries) {
        let textEn: string | null = null;
        const trimmed = e.text.trim();
        if (trimmed) {
          textEn = cache.get(trimmed) ?? null;
          if (textEn === null) {
            try {
              textEn = await this.sarvam.translateToEnglish(trimmed);
              cache.set(trimmed, textEn);
            } catch (err) {
              // A failed translation must not sink the whole transcript.
              const m = err instanceof Error ? err.message : String(err);
              this.logger.warn(`Translate failed for a turn: ${m}`);
              textEn = null;
            }
          }
        }
        entries.push({
          speakerId: e.speakerId,
          text: e.text,
          textEn,
          start: e.start,
          end: e.end,
        });
      }

      const transcriptEn = entries
        .map((e) => e.textEn ?? '')
        .filter(Boolean)
        .join(' ')
        .trim();

      // Auto-run LLM analysis (Sarvam-M) right after the transcript is ready.
      // Resilient: a failed analysis still yields a completed transcript.
      const analysis = await this.analysis.analyze(
        result.entries,
        result.transcript,
      );

      await this.prisma.callTranscript.update({
        where: { id },
        data: {
          status: 'done',
          languageCode: result.languageCode,
          transcript: result.transcript,
          transcriptEn: transcriptEn || null,
          entries: entries as unknown as object,
          analysis: (analysis as unknown as object) ?? undefined,
        },
      });
      this.logger.log(
        `Transcription ${id} done (${entries.length} turns, analysis: ${analysis ? 'yes' : 'no'}).`,
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(`Transcription ${id} failed: ${message}`);
      await this.prisma.callTranscript.update({
        where: { id },
        data: { status: 'failed', error: message },
      });
    } finally {
      // Audio is discarded after processing, success or failure.
      await fs.rm(tempPath, { force: true }).catch(() => undefined);
    }
  }
}
