---
description: Stop rewriting the spinner verbs and restore Claude's normal thinking words
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh":*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh" spinner-off`

Tell the user the spinner is back to normal and that `/water-on` turns it back on.
The ledger keeps counting either way.
