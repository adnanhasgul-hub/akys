#!/usr/bin/env bash
set -euo pipefail
# Separate demo backend. Keep exported data OUTSIDE the repository/build directory.
data_dir="${AKYS_V2_EMULATOR_DATA:-../akys-v2-emulator-data}"
extra=()
if [ -f "$data_dir/firebase-export-metadata.json" ]; then extra+=(--import "$data_dir"); fi
firebase emulators:start --config firebase.v2-emulator.json --project demo-akys --only firestore,auth --export-on-exit "$data_dir" "${extra[@]}"
