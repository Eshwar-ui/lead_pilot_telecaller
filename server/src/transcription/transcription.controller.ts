import {
  BadRequestException,
  Controller,
  Get,
  HttpCode,
  NotFoundException,
  Param,
  Post,
  UploadedFile,
  UseInterceptors,
  Body,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { TranscriptionService } from './transcription.service';
import { TranscribeResponseDto } from './dto/transcribe-response.dto';

@Controller('calls')
export class TranscriptionController {
  constructor(private readonly transcription: TranscriptionService) {}

  /// Accepts the captured recording, kicks off the Sarvam batch job, and
  /// returns immediately with a job id the client polls.
  @Post('transcribe')
  @HttpCode(202)
  @UseInterceptors(FileInterceptor('audio'))
  async submit(
    @UploadedFile() audio: Express.Multer.File | undefined,
    @Body('leadId') leadId: string,
    @Body('recordedAt') recordedAt?: string,
  ): Promise<TranscribeResponseDto> {
    if (!audio) throw new BadRequestException('Missing "audio" file.');
    if (!leadId) throw new BadRequestException('Missing "leadId".');

    return this.transcription.submit({
      buffer: audio.buffer,
      originalName: audio.originalname,
      leadId,
      recordedAt,
    });
  }

  /// Poll the status / result of a transcription job.
  @Get('transcribe/:id')
  async status(@Param('id') id: string): Promise<TranscribeResponseDto> {
    const result = await this.transcription.get(id);
    if (!result) throw new NotFoundException(`No transcription job ${id}.`);
    return result;
  }
}
