# LeadPilot — Call Transcription & Analysis Runbook

How to run, test, and troubleshoot the call-recording → Sarvam transcription →
LLM analysis pipeline. The backend + database run in **Docker** (`/server`); the
Flutter app runs on the phone.

---

## 1. What this does

```
Telecaller makes a normal call (Xiaomi dialer auto-records the MP3)
   │
Flutter app finds the recording → uploads to backend
   │  POST /calls/transcribe  →  { jobId, status:"processing" }
   ▼
NestJS backend (in-process async job, in Docker):
   1. Sarvam Batch STT (saaras:v3, diarized)   → original transcript + speaker turns
   2. Sarvam translate (per turn → en-IN)      → English
   3. Sarvam chat (sarvam-m)                    → summary + scores (Score/Summary tabs)
   4. store in Postgres (Docker), DELETE the audio
   ▼
App polls GET /calls/transcribe/:jobId until status:"done"
   → Transcript tab (speaker bubbles + English toggle), Score & Summary tabs
```

**Android-only** (iOS has no call-recording API). Capture works on Xiaomi/MIUI
with "auto record calls" enabled in the dialer; Pixel/stock Android can't expose
the file.

---

## 2. Prerequisites

| Tool | Notes |
|------|-------|
| Docker Desktop | runs the backend + Postgres. Must be **running** before any compose command. |
| Flutter SDK | for the app (runs on the host / phone, not in Docker) |
| Sarvam API key | in `server/.env` |
| Xiaomi test phone | auto-record ON, on the **same Wi-Fi** as this Mac |

---

## 3. Ports & layout

| Service | Container | Host | Notes |
|---------|-----------|------|-------|
| Backend (NestJS) | 3000 | **3000** | the app talks to this |
| Postgres | 5432 | **5433** | 5432 is used by another local project, so host is 5433 |

Inside the compose network the backend reaches Postgres at host `db:5432`.
The app reaches the backend at this Mac's LAN IP (`http://192.168.31.132:3000`).

---

## 4. Run everything (Docker)

```bash
# 0. Make sure Docker Desktop is running:  open -a Docker
cd server

# Build images + start backend & db (first run builds; later runs are instant)
docker compose up -d --build

# Watch logs (Sarvam job, analysis, errors)
docker compose logs -f backend

# Status
docker compose ps
```

Migrations apply automatically on backend startup (`prisma migrate deploy`).

Then run the app on the phone:
```bash
# from the project root, phone on the same Wi-Fi
flutter run
```

---

## 5. Stop / restart / rebuild

```bash
cd server

docker compose stop                 # stop containers (keep them + data)
docker compose start                # start them again
docker compose down                 # remove containers + network (DATA KEPT in volume)
docker compose down -v              # remove containers + WIPE the database volume

# After changing backend code (src/**) — rebuild just the backend:
docker compose up -d --build backend

# After changing .env — recreate so it's picked up:
docker compose up -d
```

---

## 6. Configuration — `server/.env`

```bash
SARVAM_API_KEY=sk_...                                    # Sarvam dashboard → API Keys
DATABASE_URL=postgresql://kalyan@localhost:5433/leadpilot # host access (psql, host-run backend)
SARVAM_CHAT_MODEL=sarvam-m   # analysis model; bump to sarvam-30b / sarvam-105b for stronger scoring
PORT=3000
```

- `.env` is gitignored — never commit it.
- In Docker, compose **overrides** `DATABASE_URL` to `postgresql://kalyan@db:5432/leadpilot`
  (see `docker-compose.yml`). The localhost:5433 value is only for running the
  backend or `psql` from the host.
- App-side config: `lib/src/core/api/api_config.dart` → `ApiEnvironment.dev.baseUrl`.

---

## 7. Test the backend without the app

```bash
# Submit a recording
curl -F audio=@/path/to/sample_call.mp3 -F leadId=test123 \
     http://localhost:3000/calls/transcribe
# → {"jobId":"<uuid>","status":"processing"}

# Poll until done
curl http://localhost:3000/calls/transcribe/<jobId>
# → {"status":"done","languageCode":"hi-IN","transcript":"…",
#     "entries":[…],"analysis":{summary,keyPoints,nextSteps,scores,breakdown,…}}
```

Inspect the database (inside the container):
```bash
docker compose exec db psql -U kalyan -d leadpilot \
  -c 'SELECT id, status, "languageCode", "createdAt" FROM "CallTranscript" ORDER BY "createdAt" DESC LIMIT 5;'
```

---

## 8. Database migrations

Existing migrations apply automatically on backend start. To **create a new**
migration after editing `prisma/schema.prisma`, run `migrate dev` from the host
against the Docker DB (it needs a shadow DB the deploy command doesn't):

```bash
cd server
DATABASE_URL=postgresql://kalyan@localhost:5433/leadpilot \
  npx prisma migrate dev -n <change_name>
docker compose up -d --build backend   # rebuild so the container ships the new migration
```

---

## 9. Common changes

**Wi-Fi / IP changed (phone can't reach backend):**
```bash
ipconfig getifaddr en0
```
Put it in `lib/src/core/api/api_config.dart` → `dev` baseUrl as
`http://<that-ip>:3000`, then hot-restart the app.

**Use the Android emulator instead of the phone:** set the baseUrl to
`http://10.0.2.2:3000`.

**Analysis JSON malformed / weak scores:** set `SARVAM_CHAT_MODEL=sarvam-30b` in
`server/.env`, then `docker compose up -d`.

---

## 10. Verify / build (without Docker)

```bash
cd server && npm run build     # backend type-check
flutter analyze lib/           # app static analysis
```

---

## 11. Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `Cannot connect to the Docker daemon` | Docker Desktop isn't running → `open -a Docker`, wait, retry. |
| `Bind for 0.0.0.0:5433 failed: port is already allocated` | Another process holds the host port. `lsof -nP -iTCP:5433 -sTCP:LISTEN`. Change the host port in `docker-compose.yml` if needed. |
| App: "Could not reach the transcription service" | Backend container down, wrong LAN IP in `api_config.dart`, or phone on a different Wi-Fi. Test: `curl http://<ip>:3000/calls/transcribe/x` from another device. |
| App: "No recording found" | Auto-record off in the Xiaomi dialer, or a different folder — check `lib/src/services/call_recording_service.dart`. |
| Backend logs show DB connection error | DB container not healthy yet: `docker compose ps`, `docker compose logs db`. |
| Job stuck on `processing` | Backend restarted mid-job (in-process, no queue yet) — re-submit. Or a Sarvam error: `docker compose logs backend`. |
| Need a clean DB | `docker compose down -v && docker compose up -d --build`. |

Logs: `docker compose logs -f backend` · `docker compose logs -f db`

---

## 12. Known limitations (pilot)

- In-process job (no Redis/BullMQ): a backend restart mid-job loses that job.
- Transcript + analysis complete together before `status:done` — the app shows
  "Transcribing…" until both are ready.
- Speaker labels are a heuristic (first speaker = telecaller "You").
- Dev backend is http + cleartext + open CORS — move to HTTPS for production.
- Host Postgres port is **5433** (not the default 5432) to avoid a clash with
  another local project.
