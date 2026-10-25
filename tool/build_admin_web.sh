#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/mobile"
flutter build web --release --target=lib/main_admin.dart --output="${ADMIN_WEB_OUTPUT:-build/admin-web}" "$@"
python3 - <<'PY'
import json
import os
from pathlib import Path
root = Path(os.environ.get('ADMIN_WEB_OUTPUT', 'build/admin-web'))
p = root / 'manifest.json'
m = json.loads(p.read_text())
m.update(name='Save Food Administrácia', short_name='Administrácia', orientation='any', description='Správa platformy Save Food.')
p.write_text(json.dumps(m, ensure_ascii=False, indent=2))
p = root / 'index.html'
p.write_text(p.read_text().replace('<title>Save Food</title>', '<title>Save Food Administrácia</title>'))
PY
