#!/usr/bin/env bash
# Run only after the Flutter SDK is activated. One benchmark VM at a time.
# Existing complete results are checked and reused; inconsistent files stop the run.
set -euo pipefail
output_dir="${1:?usage: run_isolated.sh OUTPUT_DIRECTORY}"
revision="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain=v1 -uall)" ]]; then
  printf 'Working tree must be clean before benchmarking.\n' >&2
  exit 1
fi
mkdir -p "$output_dir"
for spec in '6 30 mixed' '10 30 ratio' '15 31 surplus' '20 31 rank'; do
  read -r people days variant <<< "$spec"
  for repeat in 1 2 3; do
    for strategy in deadends combined twophase bounded; do
      target="$output_dir/${people}-${variant}-${strategy}-${repeat}.json"
      if [[ -e "$target" ]]; then
        python3 - "$target" "$people" "$days" "$variant" "$strategy" "$repeat" "$revision" <<'PY'
import json, sys
path, people, days, variant, strategy, repeat, revision = sys.argv[1:]
with open(path) as f: p = json.load(f)
assert (p['people'], p['days'], p['variant'], p['strategy'], p['repeat']) == (int(people), int(days), variant, strategy, int(repeat))
assert p['sourceRevision'] == revision
assert len(p['marks']) == 2 or (len(p['marks']) == 1 and p['marks'][0]['status'] in ('optimal', 'infeasible'))
PY
        printf 'reused %s\n' "$target"
        continue
      fi
      tmp_file="$(mktemp "$output_dir/.akys-15f.XXXXXX")"
      if dart --packages=.dart_tool/package_config.json tool/solver_v2/isolated_compare.dart "$people" "$days" "$variant" "$strategy" "$repeat" > "$tmp_file"; then
        mv "$tmp_file" "$target"
      else
        rm -f "$tmp_file"
        exit 1
      fi
      printf 'completed %s\n' "$target"
    done
  done
done
