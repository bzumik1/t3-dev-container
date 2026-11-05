---
name: t3-handover
description: Hand work to another agent, provider or thread in T3 Code, or continue work that another agent started. Use before delegating a task, moving a thread into a worktree, forking a thread, or picking up an unfinished branch, PR or issue.
---

# Hand work over in T3 Code

Codex, Claude Code and OpenCode all work on this repository through T3 Code, and any of them may continue another one's work.

## State lives in the repository

One agent's conversation and memory are invisible to the others. Before you hand over or stop, put what the next agent needs into a commit, the PR or the issue: what was done, what was verified, what was not, and what is still open. A rule that should last goes in `AGENTS.md` or a skill, never only in one agent's memory or in `CLAUDE.md`.

## T3 tools

They exist only in a session started by T3, and T3 gives the agent their exact rules.

| Need | Tool | Keep in mind |
|---|---|---|
| A task for another agent or provider | `delegate_task` | The child gets only `task`, with no history of the parent, so the brief must stand on its own. |
| A separate checkout or PR per child | `delegate_task` with `isolation: "worktree"` | It starts from the parent commit, so **uncommitted edits stay out**. Commit first. |
| Move this thread to its own branch | `t3_worktree_handoff` | It ends the live session. Pass `continuationPrompt`, or the thread just waits. |
| Branch off a thread, or bring its context back | `t3_thread_transfer` (`fork`, `merge_back`) | It moves conversation context, not files. |

Agents that run at the same time need separate worktrees and branches. By default a child shares the parent's checkout, so parallel edits there collide.

## Picking up work

Start from the branch, its commits and the PR or issue, not from memory. Re-run the skill `check-change` before you build on someone else's result.
