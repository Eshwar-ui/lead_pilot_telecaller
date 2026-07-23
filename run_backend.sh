#!/usr/bin/env bash
# Launch the FastAPI backend (leadpilot-backend) for the Flutter app.
# Usage:  ./run_backend.sh        (from the leadpilot-telecaller-app folder)
# See RUNBOOK.md for one-time setup (venv, deps, .env).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$HERE/../leadpilot-backend"

if [[ ! -d "$BACKEND" ]]; then
  echo "✗ Backend not found at: $BACKEND" >&2
  exit 1
fi
cd "$BACKEND"

# DATABASE_URL in .env defaults to the live Supabase DB, so local Postgres is NOT
# required for the common case. This only matters if you've switched DATABASE_URL
# to a local Postgres instance (see RUNBOOK.md §1a) — start it if so.
if grep -q '^DATABASE_URL=postgresql://.*@localhost' .env 2>/dev/null; then
  if command -v pg_isready >/dev/null 2>&1 && ! pg_isready -q; then
    echo "→ Starting local PostgreSQL…"
    brew services start postgresql@14 >/dev/null 2>&1 || \
      pg_ctl -D /opt/homebrew/var/postgresql@14 -l /tmp/pg14.log start || true
  fi
fi

if [[ ! -x ".venv/bin/python" ]]; then
  echo "✗ No venv at $BACKEND/.venv — run the one-time setup in RUNBOOK.md §1b" >&2
  exit 1
fi
# shellcheck disable=SC1091
source .venv/bin/activate

echo "→ Backend on http://0.0.0.0:8000  (docs: http://localhost:8000/docs)"
exec python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
