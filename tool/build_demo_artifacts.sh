#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
demo_api_port="${DEMO_PORT:-8080}"
flutter pub get
(cd apps/mobile && flutter build web --release --no-pub --dart-define="API_BASE_URL=http://127.0.0.1:$demo_api_port" --dart-define=SKIP_ONBOARDING=true)
bash tool/build_merchant_web.sh --no-pub --dart-define="API_BASE_URL=http://127.0.0.1:$demo_api_port"
bash tool/build_admin_web.sh --no-pub --dart-define="API_BASE_URL=http://127.0.0.1:$demo_api_port"
mkdir -p artifacts
(cd apps/mobile && flutter build apk --debug --no-pub --dart-define=API_BASE_URL=)
cp apps/mobile/build/app/outputs/flutter-apk/app-debug.apk artifacts/save-food-demo.apk
(cd apps/mobile && flutter build apk --debug --no-pub --dart-define="API_BASE_URL=http://10.0.2.2:$demo_api_port" --dart-define=SKIP_ONBOARDING=true)
cp apps/mobile/build/app/outputs/flutter-apk/app-debug.apk artifacts/save-food-server-emulator.apk
