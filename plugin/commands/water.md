---
description: Show the water ledger - how much this session, today, and all time, plus milestone progress
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh":*)
---

Run the ledger report and show it to the user verbatim:

!`sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh" report --session "${CLAUDE_SESSION_ID:-$CLAUDE_CODE_SESSION_ID}"`

Present the table and milestone progress as-is. Do not recompute anything, do not
editorialize about the environment, and do not add a disclaimer beyond the one the
report already carries. If the user asks where the numbers come from, point them at
`~/.claude/water/model.json`.
