#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'Usage: bash tool/build_hetzner_web.sh <assigned-public-IPv4> [web-config.json]' >&2
  exit 2
fi
hetzner_ip="$(python3 - "$1" <<'PY'
import ipaddress
import sys
try:
    value = ipaddress.IPv4Address(sys.argv[1])
except ipaddress.AddressValueError:
    sys.exit('Provide the assigned public IPv4, without https:// or a port.')
if not value.is_global:
    sys.exit('A public routable IPv4 is required; examples/private IPs cannot obtain this certificate.')
print(value)
PY
)"
hetzner_api_port="${HETZNER_API_PORT:-8443}"
if ! [[ "$hetzner_api_port" =~ ^[0-9]+$ ]] || (( hetzner_api_port < 1 || hetzner_api_port > 65535 )); then
  echo 'HETZNER_API_PORT must be a TCP port between 1 and 65535.' >&2
  exit 2
fi
hetzner_api="https://$hetzner_ip:$hetzner_api_port"
hetzner_options=(--no-pub)
if [[ $# -eq 2 ]]; then
  hetzner_config="$(python3 - "$2" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]).resolve(strict=True)
json.loads(p.read_text())
print(p)
PY
)"
  hetzner_options+=(--dart-define-from-file="$hetzner_config")
fi
hetzner_options+=(--dart-define="API_BASE_URL=$hetzner_api")
(cd apps/mobile && flutter build web --release --output=build/hetzner-web "${hetzner_options[@]}")
MERCHANT_WEB_OUTPUT=build/hetzner-merchant-web bash tool/build_merchant_web.sh "${hetzner_options[@]}"
ADMIN_WEB_OUTPUT=build/hetzner-admin-web bash tool/build_admin_web.sh "${hetzner_options[@]}"
