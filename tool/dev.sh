#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f apps/api/.env ]]; then
  set -a
  source apps/api/.env
  set +a
fi
flutter pub get
dart run apps/api/bin/server.dart &
api_pid=$!
trap 'kill "$api_pid" 2>/dev/null || true' EXIT INT TERM
api_port="${PORT:-8080}"
for attempt in {1..30}; do
  kill -0 "$api_pid" 2>/dev/null || { echo "API failed to start; check the port and configuration." >&2; exit 1; }
  if curl -fsS "http://127.0.0.1:$api_port/health" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
(cd apps/mobile && flutter run -d chrome --web-port=7357 --dart-define="API_BASE_URL=http://127.0.0.1:$api_port")
