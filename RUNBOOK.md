# LeadPilot — Run Backend + Flutter App

How to start the **FastAPI backend** (`leadpilot-backend`) and the **Flutter app**
(`leadpilot-telecaller-app`, this folder) together on macOS.

```
Client-project/Lead Pilot/
  leadpilot-backend/          ← FastAPI backend (Python, port 8000)
  leadpilot-telecaller-app/   ← Flutter app (this folder)
```

> For the project-wide picture (backend + founder web + this app, local **and**
> production links) see [`../RUNBOOK.md`](../RUNBOOK.md) at the project root. This file
> is the telecaller-specific deep dive.

The app ships pointed at the **production** backend by default (see §2a) — it works
out of the box without running anything locally. Run the backend locally only when you
need to test against unreleased backend changes. If the configured backend is
unreachable the app falls back to mock data automatically — the UI stays up but you
won't see live leads or call scores.

---

## Prerequisites (one-time)

| Tool | Check | Install |
|---|---|---|
| Flutter 3.x | `flutter --version` | https://docs.flutter.dev/get-started |
| Python 3.11+ | `python3 --version` | `brew install python@3.11` |
| ffmpeg | `ffmpeg -version` | `brew install ffmpeg` |
| Sarvam API key | — | https://dashboard.sarvam.ai |

PostgreSQL is **not** required for the common case — `leadpilot-backend/.env` points
`DATABASE_URL` at a live Supabase Postgres DB, shared with production. Only install
local PostgreSQL if you deliberately want an isolated local DB (see §1a).

---

## 1. Backend — `leadpilot-backend/` (port 8000)

### 1a. Database — Supabase by default (skip unless you want a local DB)

`leadpilot-backend/.env` already has `DATABASE_URL` set to the live Supabase project
(direct connection, port 5432) — the same DB production uses. Nothing to start locally.

To use an isolated local DB instead:
```bash
brew install postgresql@14
brew services start postgresql@14
createdb voicesummary
```
then set `DATABASE_URL=postgresql://<you>@localhost:5432/voicesummary` in `.env`.
Tables are created automatically on first startup either way.

### 1b. Python environment (once)

A `.venv` already exists at `leadpilot-backend/.venv` on this machine — just activate
it. For a fresh clone:

```bash
cd "../leadpilot-backend"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

No extra packages needed beyond `requirements.txt` — transcription/analysis runs
entirely through Sarvam AI (`app/utils/sarvam.py`); there's no local
matplotlib/Whisper dependency in the current backend.

### 1c. `.env` file (once)

```bash
cd "../leadpilot-backend"
cp .env.example .env
```
(`.env.example` is the current, complete template — includes the `JWT_SECRET_KEY` the
app now requires at boot. Ignore the older `env.example` file in that repo, it's stale.)

Edit `.env` — minimum required values:

```env
DATABASE_URL=postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require
SARVAM_API_KEYS=your_key_here
SARVAM_CHAT_MODEL=sarvam-105b
SARVAM_STT_MODEL=saaras:v3
SARVAM_STT_MODE=transcribe
STORAGE_MODE=local
LOCAL_STORAGE_PATH=./local_storage
AUDIO_SOURCE_PATH=./Audio
JWT_SECRET_KEY=<generate: python3 -c "import secrets; print(secrets.token_hex(32))">
APP_HOST=0.0.0.0
APP_PORT=8000
DEBUG=true
```

### 1d. Start the backend

```bash
cd "../leadpilot-backend"
source .venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Or just run [`./run_backend.sh`](run_backend.sh) from this folder — it does the above.

`--host 0.0.0.0` is required so a physical phone on your Wi-Fi/USB can reach it.
Tables are created automatically on first startup.

API docs: http://localhost:8000/docs

### 1e. Smoke-test

```bash
curl http://localhost:8000/health
curl http://localhost:8000/api/inbox

# Create a demo lead (appears in inbox immediately):
curl -X POST http://localhost:8000/api/leads \
  -H 'Content-Type: application/json' \
  -d '{"name":"Sneha Reddy","phone":"+919876543210","source":"google","reason":"Wants 3BHK"}'

# Load sample audio from Audio/ + run full AI analysis (needs SARVAM_API_KEYS):
python scripts/import_audio.py
```

---

## 2. Flutter app — `leadpilot-telecaller-app/` (this folder)

### 2a. Which backend it talks to

[`lib/src/core/api/api_config.dart`](lib/src/core/api/api_config.dart) defines the
target. **Currently set to production**:

```dart
static const ApiEnvironment environment = ApiEnvironment.prod;
// prod baseUrl = https://leadpilot-backend-perc.onrender.com
```

To point it at a locally-running backend (§1) instead, change `environment` to
`ApiEnvironment.dev` and set `ApiEnvironment.dev.baseUrl`:

| Target | Value |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| Physical phone, same Wi-Fi as Mac | `http://<mac-LAN-IP>:8000` |
| Physical phone over USB | `http://127.0.0.1:8000` + `adb reverse tcp:8000 tcp:8000` (this is the current default in `dev` — see the in-file comment for why: the dev Wi-Fi has AP isolation, so USB+adb reverse is the only path that works) |
| iOS simulator / macOS desktop | `http://localhost:8000` |

Find your Mac's LAN IP:
```bash
ipconfig getifaddr en0      # e.g. 192.168.31.132
```

`ApiConfig.useMockData` is `false` (live backend, whichever environment is active).
Set it to `true` to run the UI fully offline.

### 2b. Run

```bash
flutter pub get
flutter devices
flutter run                 # or: flutter run -d <deviceId>
```

---

## 3. Quick-start (both together, local backend)

**Terminal 1 — backend:**
```bash
cd "/Users/kalyan/Client-project/Lead Pilot/leadpilot-backend"
source .venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Terminal 2 — Flutter** (after switching `api_config.dart` to `ApiEnvironment.dev`, §2a):
```bash
cd "/Users/kalyan/Client-project/Lead Pilot/leadpilot-telecaller-app"
flutter run
```

Or skip both local steps entirely — `flutter run` alone already talks to production.

---

## 4. Backend module layout

`app/api/` (all wired in `app/main.py`):

| File | Responsibility |
|---|---|
| `calls.py` | Call CRUD, upload pipeline, transcript, per-call score/analysis (`/api/calls/*`, `/api/inbox`, `/api/leads/*`, `/api/memory/*`) |
| `dashboard.py` | Founder dashboard metrics, revenue, leaderboard |
| `team.py` | Team roster + telecaller performance |
| `attendance.py` | Shift check-in/out, forgotten-checkout correction |
| `auth.py` | Login (founder + telecaller), JWT issuance |
| `follow_ups.py` | Follow-up scheduling |

Exact endpoints + JSON shapes:
[`../leadpilot-backend/BACKEND_INTEGRATION.md`](../leadpilot-backend/BACKEND_INTEGRATION.md).

---

## 5. Troubleshooting

| Symptom | Fix |
|---|---|
| App shows mock data | Configured backend unreachable — check it's running (if `dev`) and `baseUrl`/LAN IP is correct. Phone + Mac must be on same Wi-Fi, or use USB + `adb reverse`. |
| `connection refused :8000` from phone | Start backend with `--host 0.0.0.0` not `127.0.0.1` |
| "can't connect to server" / network error to `127.0.0.1:8000` | `adb reverse` tunnel dropped (happens on every ADB/USB reconnect). Run `adb reverse tcp:8000 tcp:8000`, or keep it alive with `./tool/keep-adb-reverse.sh` in a spare terminal. Check `adb reverse --list` first. |
| Android CLEARTEXT error | Use a debug build; release blocks plain HTTP by default |
| Inbox empty (local backend) | Run `python scripts/import_audio.py` or `POST /api/leads` (step 1e) |
| Score tab shows `--` | Analysis not complete — wait ~60 s after upload then re-open the lead |
| Wrong LAN IP | Re-run `ipconfig getifaddr en0` and update `ApiEnvironment.dev.baseUrl` |
| `JWT_SECRET_KEY` missing / backend won't boot | Set it in `leadpilot-backend/.env` (see §1c) — the app now requires it at startup |
