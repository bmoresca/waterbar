#!/bin/sh
# Hook entry point. Prefers WaterBar.app's built-in engine - it needs no
# interpreter at all - and falls back to the Python engine when the app isn't
# installed (or when Claude Code isn't running on a Mac).
#
# Whichever runs, both write the same ledger: the two engines are kept
# byte-identical, and there's a parity test in scripts/parity-check.sh.

# The marker file is written by build.sh. Without it we could be looking at a
# WaterBar old enough to have no CLI mode, which would silently open a menu bar
# item and never exit - hanging the hook instead of answering it.
for bundle in \
    "/Applications/WaterBar.app" \
    "$HOME/Applications/WaterBar.app"
do
    if [ -x "$bundle/Contents/MacOS/WaterBar" ] && [ -f "$bundle/Contents/Resources/cli-engine" ]; then
        exec "$bundle/Contents/MacOS/WaterBar" "$@"
    fi
done

# On macOS, /usr/bin/python3 is only a stub until the Command Line Tools are
# installed - running it before then pops an installer dialog mid-session. So
# prefer a real interpreter, and only fall back to /usr/bin/python3 once the
# tools are actually present.
PY=""
for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -x "$candidate" ] && PY="$candidate" && break
done
if [ -z "$PY" ]; then
    if [ "$(uname)" != "Darwin" ] || xcode-select -p >/dev/null 2>&1; then
        PY="$(command -v python3 2>/dev/null)"
    fi
fi

if [ -z "$PY" ]; then
    # Nothing to run with. Stay silent rather than break the session.
    [ "$1" = "statusline" ] || echo '{"suppressOutput": true}'
    exit 0
fi

exec "$PY" "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/engine/water.py" "$@"
