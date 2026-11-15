#!/usr/bin/env bash
set -euo pipefail
# Local-only package: never invokes Hosting or changes V1 production workflow.
flutter build web --release --no-pub --no-web-resources-cdn -t lib/main_v2.dart "$@"
bash tool/solver_v2/web/build_worker.sh build/web
