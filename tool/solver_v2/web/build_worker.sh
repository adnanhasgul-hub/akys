#!/usr/bin/env bash
set -euo pipefail
# Run at repository root AFTER flutter build web when packaging with Flutter.
output_dir="${1:-build/web}"
mkdir -p "$output_dir"
dart compile js -O2 --no-source-maps -o "$output_dir/akys_v2_worker.js" tool/solver_v2/web/worker_entry.dart
