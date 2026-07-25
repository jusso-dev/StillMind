#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shots_dir="${1:-$script_dir/../screenshots}"

caption_for() {
  case "$1" in
    *01Home*)       echo "A private place for every thought" ;;
    *02Capture*)    echo "Capture a thought in seconds" ;;
    *03Journal*)    echo "Your journal, organised and searchable" ;;
    *04Reflection*) echo "Turn reflections into clear next steps" ;;
    *05Insights*)   echo "See gentle patterns over time" ;;
    *)              echo "StillMind" ;;
  esac
}

shopt -s nullglob
count=0
for screenshot in "$shots_dir"/*/*.png; do
  filename="$(basename "$screenshot")"
  python3 "$script_dir/frame.py" \
    "$screenshot" \
    "$(caption_for "$filename")" \
    "$screenshot"
  count=$((count + 1))
done

if [[ "$count" -eq 0 ]]; then
  echo "No screenshots found under $shots_dir" >&2
  exit 1
fi

echo "Framed $count StillMind screenshot(s) in $shots_dir"
