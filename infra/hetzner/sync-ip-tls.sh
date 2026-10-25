#!/usr/bin/env bash
# Reuse the existing host certificate. Its issuer/renewal remains unchanged.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
root="$(cd "$(dirname "$0")/.." && pwd)"
exec 9>"$root/.tls-sync.lock"
flock -n 9 || exit 0
dc=(docker compose --project-directory "$root/deploy" -f "$root/deploy/compose.yaml")
docker volume create nevyhadzuj_tls >/dev/null
docker run --rm --network none --user 0:0 --entrypoint /bin/sh \
  --mount type=volume,source=plants-be_certbot-certs,target=/certificates,readonly \
  --mount type=volume,source=nevyhadzuj_tls,target=/export \
  nginx@sha256:e7257f1ef28ba17cf7c248cb8ccf6f0c6e0228ab9c315c152f9c203cd34cf6d1 \
  -eu -c '
    cp -L /certificates/live/volkanditat-ip/fullchain.pem /export/fullchain.pem.next
    cp -L /certificates/live/volkanditat-ip/privkey.pem /export/privkey.pem.next
    chown 101:101 /export/*.next
    chmod 644 /export/fullchain.pem.next
    chmod 600 /export/privkey.pem.next
    mv /export/fullchain.pem.next /export/fullchain.pem
    mv /export/privkey.pem.next /export/privkey.pem
  '
if [[ "${1:-}" != --prepare ]]; then
  "${dc[@]}" exec -T --interactive=false proxy nginx -t
  "${dc[@]}" exec -T --interactive=false proxy nginx -s reload
fi
