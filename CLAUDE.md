# Claude Code workflow

- Delegate every repo search to the `search` (layout) or `grep` (call sites) subagent, and every test run to `audit`. Keep the main context small: work from their summaries, not raw file dumps.
