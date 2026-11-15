#!/usr/bin/env bash
set -euo pipefail
# Offline acceptance harness only; standard authenticated AKYS uses lib/main.dart.
flutter build web --release --no-pub --no-web-resources-cdn -t lib/main_v2.dart "$@"
bash tool/solver_v2/web/build_worker.sh build/web
