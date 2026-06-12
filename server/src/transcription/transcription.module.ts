import { Module } from '@nestjs/common';
import { TranscriptionController } from './transcription.controller';
import { TranscriptionService } from './transcription.service';
import { SarvamService } from './sarvam.service';
import { AnalysisService } from './analysis.service';

@Module({
  controllers: [TranscriptionController],
  providers: [TranscriptionService, SarvamService, AnalysisService],
})
export class TranscriptionModule {}
