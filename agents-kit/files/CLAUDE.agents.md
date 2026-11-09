
## Agent workflow

Main session: Sonnet 5.5. Subagents: `search`, `grep`, `audit` (Haiku 5.5) and `advisor` (Opus 5.5).

- Delegate repo searches to `search` (layout) or `grep` (call sites), and every test run to `audit`. Keep the main context small: work from their summaries, not raw file dumps.
- Before sign-off, in this order:
  1. Commit the change. `audit` runs in a separate worktree and only sees commits.
  2. Call `audit` with the branch or commit to check.
  3. Call `advisor` with the diff text (`git diff <base>...HEAD`) and the audit report pasted into the prompt.
  4. Apply what advisor asks for, commit, and run `audit` again.
- Subagents cannot call other subagents.
