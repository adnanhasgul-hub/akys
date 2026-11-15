#!/usr/bin/env bash
set -euo pipefail
# Emulator-only entry; no deploy and no production credentials.
flutter build web --release --no-pub --no-web-resources-cdn \
  --output build/v2-firebase -t lib/main_v2_firebase.dart \
  --dart-define=AKYS_V2_EMULATOR_HOST=127.0.0.1
bash tool/solver_v2/web/build_worker.sh build/v2-firebase
