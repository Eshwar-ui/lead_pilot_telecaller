import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // The Flutter app calls this directly from devices on the LAN during the
  // pilot; allow any origin. Lock this down before production.
  app.enableCors();

  const port = process.env.PORT ?? 3000;
  await app.listen(port, '0.0.0.0');
  Logger.log(`LeadPilot backend listening on http://0.0.0.0:${port}`, 'Bootstrap');
}

void bootstrap();
