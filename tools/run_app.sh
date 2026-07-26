#!/usr/bin/env bash
# HearBloom one-command launcher (macOS / Linux).
#
#   bash tools/run_app.sh          # build (release) + serve on :8080
#   bash tools/run_app.sh 9000     # choose a port
#   NOBUILD=1 bash tools/run_app.sh  # serve the existing build immediately
#
# Set HEARBLOOM_FLUTTER to the flutter executable if it is not on PATH.
# This runs the research web build locally. It is NOT a medical device.
set -euo pipefail
PORT="${1:-8080}"
FLUTTER="${HEARBLOOM_FLUTTER:-flutter}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/apps/flutter_app"
cd "$APP"
if [ "${NOBUILD:-0}" != "1" ]; then
  echo "==> Building HearBloom web (release)..."
  "$FLUTTER" build web --release
fi
if [ ! -f "$APP/build/web/index.html" ]; then
  echo "No web build found at $APP/build/web (run without NOBUILD=1)." >&2
  exit 1
fi
echo ""
echo "==> HearBloom is live at http://127.0.0.1:$PORT"
echo "    Research build - not a medical device, no diagnostic claims."
echo "    Press Ctrl+C to stop."
echo ""
python3 -m http.server "$PORT" -b 127.0.0.1 --directory "$APP/build/web"
