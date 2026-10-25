#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze --no-pub
for package in packages/marketplace_domain apps/api packages/marketplace_api; do
  (cd "$package" && dart test --reporter expanded)
done
(cd packages/marketplace_data && flutter test --no-pub --reporter expanded)
(cd apps/mobile && flutter test --no-pub --reporter expanded)
