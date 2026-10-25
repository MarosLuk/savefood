#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Private config/app.<platform>.json adds Firebase; without it only the API address is set.
defines() {
  local file="config/app.$1.json"
  [[ -f "$file" ]] || file=config/hetzner.json
  echo "--dart-define-from-file=../../$file"
}
release_keys() {
  test -f apps/mobile/android/key.properties || {
    echo 'Release signing needs apps/mobile/android/key.properties.' >&2; exit 1;
  }
}
case "${1:-android}" in
  android)
    (cd apps/mobile && flutter build apk --debug --no-pub "$(defines android)")
    mkdir -p artifacts
    cp apps/mobile/build/app/outputs/flutter-apk/app-debug.apk artifacts/save-food-hetzner.apk
    ;;
  apk)
    release_keys
    # Pub regenerates the plugin registrant without dev-only plugins such as integration_test.
    (cd apps/mobile && flutter build apk --release "$(defines android)")
    mkdir -p artifacts
    cp apps/mobile/build/app/outputs/flutter-apk/app-release.apk artifacts/save-food-hetzner-release.apk
    ;;
  aab)
    release_keys
    (cd apps/mobile && flutter build appbundle --release "$(defines android)")
    mkdir -p artifacts
    cp apps/mobile/build/app/outputs/bundle/release/app-release.aab artifacts/save-food-hetzner.aab
    ;;
  ios)
    (cd apps/mobile && flutter build ios --release --no-codesign --no-pub "$(defines ios)")
    ;;
  ipa)
    (cd apps/mobile && flutter build ipa --release --no-pub "$(defines ios)" "${@:2}")
    ;;
  *) echo 'Usage: bash tool/build_hetzner_mobile.sh [android|apk|aab|ios|ipa [export options]]' >&2; exit 2 ;;
esac
