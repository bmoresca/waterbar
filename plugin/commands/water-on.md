---
description: Put the live water estimate back in the thinking spinner
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh":*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh" spinner-on --session "${CLAUDE_SESSION_ID:-$CLAUDE_CODE_SESSION_ID}"`

Tell the user it takes effect on the next turn.
