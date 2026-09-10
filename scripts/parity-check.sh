#!/usr/bin/env bash
# Prove the Swift engine (inside WaterBar.app) and the Python engine
# (plugin/engine/water.py) produce identical output.
#
# Both run against a frozen copy of ~/.claude/projects in throwaway config
# directories, so nothing touches your real ledger.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOURCE="${1:-$HOME/.claude/projects}"
[ -d "$SOURCE" ] || { echo "No transcripts at $SOURCE"; exit 1; }

echo "==> Freezing a copy of $SOURCE"
# A real copy, not hardlinks: live sessions keep appending to their transcripts,
# and a hardlinked "snapshot" would grow underneath the second engine.
cp -R "$SOURCE" "$WORK/snapshot"
mkdir -p "$WORK/swift" "$WORK/py"
ln -s "$WORK/snapshot" "$WORK/swift/projects"
ln -s "$WORK/snapshot" "$WORK/py/projects"

BIN="$ROOT/WaterBar/WaterBar.app/Contents/MacOS/WaterBar"
if [ ! -x "$BIN" ]; then
  BIN="$(swift build -c release --package-path "$ROOT/WaterBar" --show-bin-path)/WaterBar"
  [ -x "$BIN" ] || { echo "Build WaterBar first: bash WaterBar/build.sh"; exit 1; }
fi

echo "==> Swift engine"
CLAUDE_CONFIG_DIR="$WORK/swift" "$BIN" scan >/dev/null
echo "==> Python engine"
CLAUDE_CONFIG_DIR="$WORK/py" python3 "$ROOT/plugin/engine/water.py" scan >/dev/null

echo
python3 - "$WORK" <<'PY'
import json, sys, pathlib
work = pathlib.Path(sys.argv[1])
a = json.load(open(work / "swift/water/state.json"))
b = json.load(open(work / "py/water/state.json"))
fields = ("total_ml", "requests", "tokens", "by_model",
          "by_project", "by_day", "by_session", "unlocked")
bad = [f for f in fields if a[f] != b[f]]
print("total_ml  swift=%s  python=%s" % (a["total_ml"], b["total_ml"]))
print("requests  swift=%s  python=%s" % (a["requests"], b["requests"]))
for f in fields:
    print("  %-11s %s" % (f, "ok" if a[f] == b[f] else "MISMATCH"))
sys.exit(1 if bad else 0)
PY

if diff <(sort "$WORK/swift/water/ledger.jsonl") <(sort "$WORK/py/water/ledger.jsonl") >/dev/null; then
  echo
  echo "PASS - byte-identical ledgers ($(wc -l < "$WORK/swift/water/ledger.jsonl" | tr -d ' ') rows)"
else
  echo
  echo "FAIL - ledgers differ:"
  diff <(sort "$WORK/swift/water/ledger.jsonl") <(sort "$WORK/py/water/ledger.jsonl") | head -10
  exit 1
fi
