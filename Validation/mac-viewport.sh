#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_work="$(mktemp -d /private/tmp/safience-viewport.XXXXXX)"
trap 'rm -rf "$task_work"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$task_work/cache" \
  "$task_root/Mac/Sources/PageHolder.swift" "$task_root/Validation/MacViewport.swift" \
  -o "$task_work/check"
"$task_work/check"
