#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/mobile"
flutter build web --release --target=lib/main_merchant.dart --output="${MERCHANT_WEB_OUTPUT:-build/merchant-web}" "$@"
python3 - <<'PY'
import json
import os
from pathlib import Path
root = Path(os.environ.get('MERCHANT_WEB_OUTPUT', 'build/merchant-web'))
p = root / 'manifest.json'
m = json.loads(p.read_text())
m.update(name='Save Food Predajca', short_name='Predajca', orientation='any', description='Prevádzky, sklad a automatické balíčky.')
p.write_text(json.dumps(m, ensure_ascii=False, indent=2))
p = root / 'index.html'
s = p.read_text().replace('<title>Save Food</title>', '<title>Save Food Predajca</title>')
s = s.replace('Dobré jedlo. Druhá šanca. Zachráň si chutný balíček z tvojho okolia.', 'Portál predajcu: prevádzky, sklad, ponuky a automatické balíčky.')
p.write_text(s)
PY
