#!/usr/bin/env bash
# HearBloom one-command verification (macOS / Linux / CI).
#
#   bash tools/verify_all.sh
#
# Runs backend pytest + self-test, the headless Dart harnesses, the Dart
# analyzer and the Flutter tests. Exits non-zero if any step fails.
#
# Toolchain: uses `dart` / `flutter` on PATH by default. Override with the
# HEARBLOOM_DART / HEARBLOOM_FLUTTER environment variables.
set -u
export FLUTTER_SUPPRESS_ANALYTICS=true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/flutter_app"
DART="${HEARBLOOM_DART:-dart}"
FLUTTER="${HEARBLOOM_FLUTTER:-flutter}"

failures=()
step() {
  local name="$1"; shift
  echo ""
  echo "=== $name ==="
  if ! "$@"; then
    echo "FAILED: $name"
    failures+=("$name")
  fi
}

cd "$REPO_ROOT"
step "pytest (backend)" python -m pytest -q
step "self-test" python tests/run_selftest.py

for h in catalog safety engine stage persistence results recommendation audio gap modulation sequence mci pitch rate speech openset interval chord closed battery timbre identification dichotic fatigue asr norms psychometrics diagnostics psychoacoustics tier3; do
  step "dart harness: $h" "$DART" run "apps/flutter_app/tool/verify/${h}_harness.dart"
done

step "dart analyze (lib + test)" bash -c "cd '$APP_DIR' && '$DART' analyze lib test"
step "flutter test" bash -c "cd '$APP_DIR' && '$FLUTTER' test"

echo ""
if [ ${#failures[@]} -eq 0 ]; then
  echo "ALL VERIFICATION STEPS PASSED"
  exit 0
else
  echo "FAILED STEPS: ${failures[*]}"
  exit 1
fi
