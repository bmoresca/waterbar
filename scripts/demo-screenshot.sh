#!/usr/bin/env bash
# Render the marketing screenshot from synthetic data.
#
# The popover lists your thirstiest projects by name. Rendering it against a
# real ledger publishes your project - and client - names to the README, the
# landing page and every social preview of it. So the published screenshot is
# always generated from the fake ledger below, never from ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/docs/waterbar.png}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/water"
# No projects/ directory, so the scan finds no transcripts and this state
# passes straight through to the renderer.
python3 - "$WORK/water/state.json" <<'PY'
import json, sys, datetime

projects = [
    ("acme-web/dashboard", 121.8), ("acme-web/api",     101.2),
    ("side-projects/mixtape", 88.3), ("oss/parser",      77.9),
    ("personal/notes",     27.7), ("sandbox/scratch",   12.4),
]
models = [("opus", 471.2, 9800), ("sonnet", 121.4, 5100), ("haiku", 8.9, 1400)]

today = datetime.date.today()
by_day = {}
shape = [11, 6, 19, 42, 21, 17, 13, 8, 5, 4, 14, 7, 33, 38]
for i, weight in enumerate(shape):
    day = today - datetime.timedelta(days=len(shape) - 1 - i)
    by_day[day.isoformat()] = {"ml": weight * 820.0, "requests": weight * 9}

total = 631_000.0
state = {
    "version": 1,
    "total_ml": total,
    "requests": 22634,
    "tokens": {"input": 725_000, "output": 18_900_000,
               "cache_write": 147_000_000, "cache_read": 5_300_000_000},
    "by_day": by_day,
    "by_project": {name: {"ml": litres * 1000, "requests": int(litres * 5)}
                   for name, litres in projects},
    "by_model": {name: {"ml": litres * 1000, "requests": n} for name, litres, n in models},
    "by_session": {},
    "unlocked": [],
    "first_seen": None, "last_seen": None,
    "updated_at": datetime.datetime.now().isoformat(),
}
json.dump(state, open(sys.argv[1], "w"), indent=2)
PY

BIN="$ROOT/WaterBar/WaterBar.app/Contents/MacOS/WaterBar"
[ -x "$BIN" ] || { echo "Build first: bash WaterBar/build.sh"; exit 1; }

CLAUDE_CONFIG_DIR="$WORK" "$BIN" --render-preview "$OUT" >/dev/null
mv -f "${OUT%.png}-label.png" "$ROOT/docs/menubar.png" 2>/dev/null || true
cp -f "$OUT" "$ROOT/site/waterbar.png"
echo "Rendered $OUT from synthetic data (no real project names)."
