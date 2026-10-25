#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# This command deliberately does not source .env. Demo uses its own SQLite file.
for demo_port in "${DEMO_PORT:-8080}" 7357 7358 7359; do
  if lsof -nP -iTCP:"$demo_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $demo_port is already in use. Stop the previous local demo first." >&2
    exit 1
  fi
done
flutter pub get
(cd apps/mobile && flutter build web --release --dart-define="API_BASE_URL=http://127.0.0.1:${DEMO_PORT:-8080}" --dart-define=SKIP_ONBOARDING=true)
bash tool/build_merchant_web.sh --dart-define="API_BASE_URL=http://127.0.0.1:${DEMO_PORT:-8080}"
bash tool/build_admin_web.sh --dart-define="API_BASE_URL=http://127.0.0.1:${DEMO_PORT:-8080}"
demo_pids=()
cleanup() { for demo_pid in "${demo_pids[@]}"; do kill "$demo_pid" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM
dart run apps/api/bin/demo.dart &
demo_pids+=("$!")
python3 -m http.server 7357 --bind 127.0.0.1 --directory apps/mobile/build/web &
demo_pids+=("$!")
python3 -m http.server 7358 --bind 127.0.0.1 --directory apps/mobile/build/merchant-web &
demo_pids+=("$!")
python3 -m http.server 7359 --bind 127.0.0.1 --directory apps/mobile/build/admin-web &
demo_pids+=("$!")
echo 'Customer: http://127.0.0.1:7357 · Merchant: http://127.0.0.1:7358 · Admin: http://127.0.0.1:7359'
wait
