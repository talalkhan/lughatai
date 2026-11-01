@AGENTS.md

# Claude Code specifics

- Everything above is imported from `AGENTS.md`; it is the single source of truth for all agents. Do not duplicate instructions here.
- A `SessionStart` hook (`.claude/settings.json`) runs `scripts/agent_status.sh` so each session opens with live repo state. If it did not run, run it yourself first.
- Cloud sessions have no `gh` CLI; use the GitHub MCP tools.
