#!/usr/bin/env bash
# Local builds only; the shared host receives the runtime image and static assets.
set -euo pipefail
cd "$(dirname "$0")/.."
release="${DEPLOY_RELEASE:-$(date -u +%Y%m%dT%H%M%SZ)}"
image="${API_IMAGE:-nevyhadzuj-api:hetzner-$release}"
host="${DEPLOY_SSH:-marosko@46.62.223.67}"
key="${DEPLOY_KEY:-$HOME/.ssh/hetzner_gateway}"
[[ "$release" =~ ^[a-zA-Z0-9_-]+$ && "$image" =~ ^nevyhadzuj-api:[a-zA-Z0-9_.-]+$ ]] || exit 2
ssh_args=(-o BatchMode=yes -o IdentitiesOnly=yes -i "$key")
if [[ "${1:-}" != --skip-build ]]; then
  flutter pub get
  HETZNER_API_PORT=8453 bash tool/build_hetzner_web.sh 46.62.223.67 config/hetzner.json
  docker buildx build --platform linux/amd64 --load -t "$image" -f apps/api/Dockerfile .
fi
[[ "$(docker image inspect "$image" --format '{{.Architecture}}')" == amd64 ]] || {
  echo 'The server requires an amd64 image.' >&2; exit 1;
}
for directory in hetzner-web hetzner-merchant-web hetzner-admin-web; do
  test -s "apps/mobile/build/$directory/main.dart.js"
done
ssh "${ssh_args[@]}" "$host" 'mkdir -p ~/save-food/deploy ~/save-food/releases && chmod 700 ~/save-food'
rsync -az -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key" infra/hetzner/ "$host:save-food/deploy/"
ssh "${ssh_args[@]}" "$host" "mkdir -p save-food/releases/$release/web save-food/releases/$release/merchant-web save-food/releases/$release/admin-web"
for pair in 'hetzner-web web' 'hetzner-merchant-web merchant-web' 'hetzner-admin-web admin-web'; do
  read -r source target <<< "$pair"
  rsync -az -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key" \
    "apps/mobile/build/$source/" "$host:save-food/releases/$release/$target/"
done
docker save "$image" | gzip | ssh "${ssh_args[@]}" "$host" 'gzip -d | docker load'
ssh "${ssh_args[@]}" "$host" bash -s -- "$release" "$image" <<'REMOTE'
set -euo pipefail
release="$1"
image="$2"
root="$HOME/save-food"
cd "$root/deploy"
if [[ ! -f .env ]]; then cp .env.example .env; fi
chmod 600 .env
cp -p .env ".env.before-$release"
sed -i "s|^API_IMAGE=.*|API_IMAGE=$image|" .env
previous="$(readlink "$root/current" || true)"
ln -s "releases/$release" "$root/current.next"
mv -Tf "$root/current.next" "$root/current"
bash ./sync-ip-tls.sh --prepare
docker compose config --quiet
if ! docker compose up -d --no-build --force-recreate --wait --wait-timeout 120 </dev/null; then
  if [[ -n "$previous" ]]; then
    cp -p ".env.before-$release" .env
    ln -s "$previous" "$root/current.rollback"
    mv -Tf "$root/current.rollback" "$root/current"
    docker compose up -d --no-build --force-recreate --wait --wait-timeout 120 </dev/null
  fi
  exit 1
fi
cron_file="$(mktemp)"
trap 'rm -f "$cron_file"' EXIT
crontab -l > "$cron_file"
if ! grep -q '# save-food-ip-tls$' "$cron_file"; then
  printf '7 * * * * /bin/bash %s/deploy/sync-ip-tls.sh >> %s/tls-sync.log 2>&1 # save-food-ip-tls\n' "$root" "$root" >> "$cron_file"
  crontab "$cron_file"
fi
docker compose ps
REMOTE
curl --connect-timeout 10 --max-time 30 --fail --silent --show-error https://46.62.223.67:8453/health/ready
