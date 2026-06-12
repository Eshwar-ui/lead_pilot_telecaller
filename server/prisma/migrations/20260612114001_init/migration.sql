-- CreateTable
CREATE TABLE "CallTranscript" (
    "id" TEXT NOT NULL,
    "leadId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'processing',
    "languageCode" TEXT,
    "transcript" TEXT,
    "transcriptEn" TEXT,
    "entries" JSONB,
    "analysis" JSONB,
    "error" TEXT,
    "recordedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CallTranscript_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CallTranscript_leadId_idx" ON "CallTranscript"("leadId");
