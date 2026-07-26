#!/usr/bin/env bash
set -euo pipefail
out="${1:-stimuli/demo/speech_macos}"; mkdir -p "$out"
while IFS='|' read -r id text; do say -o "$out/$id.aiff" "$text"; done <<'EOF'
w001|Please close the blue window.
w002|Meet me near the main entrance.
w003|The class begins at nine thirty.
w004|Turn left after the second signal.
w005|Write down the name and phone number.
w006|The meeting moved to Friday afternoon.
w007|Bring the red folder and two pens.
w008|Call me when you reach the station.
w009|The teacher changed the final question.
w010|Order tea without sugar, please.
EOF
echo 'Generated demo system-voice files; not validated clinical stimuli.'
