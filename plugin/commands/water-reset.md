---
description: Wipe the water ledger and all unlocked milestones back to zero
argument-hint: "[confirm]"
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh":*)
---

The user wants to reset the water ledger. This deletes the ledger, the cursor, the
running state, and every unlocked milestone. It cannot be undone, and the next scan
will re-count from the transcripts still on disk (so the total will partly come back).

Arguments given: $ARGUMENTS

If the arguments do not contain the word `confirm`, do NOT run anything. Explain what
reset does and ask the user to run `/water-reset confirm`.

If they did confirm, run:

```
sh "${CLAUDE_PLUGIN_ROOT}/hooks/water-hook.sh" reset
```

then report the result in one line.
