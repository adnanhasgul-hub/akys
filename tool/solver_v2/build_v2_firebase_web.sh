#!/usr/bin/env bash
set -euo pipefail
# Emulator-only entry; no deploy and no production credentials.
flutter build web --release --no-pub --no-web-resources-cdn \
  --output build/v2-firebase -t lib/main.dart \
  --dart-define=AKYS_V2_EMULATOR_HOST=127.0.0.1
bash tool/solver_v2/web/build_worker.sh build/v2-firebase
# Pin to FlutterFire's SDK; this local-only HTML shim never enters build/web.
cp tool/solver_v2/web/emulator_bootstrap.js build/v2-firebase/emulator_bootstrap.js
python3 - <<'PY'
from pathlib import Path
p = Path('build/v2-firebase/index.html')
s = p.read_text().replace('<script src="flutter_bootstrap.js" async></script>', '<script type="module" src="emulator_bootstrap.js"></script>')
p.write_text(s)
PY
