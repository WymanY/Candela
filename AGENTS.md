# Agent notes

These rules apply only to this Candela repository.

## Issue tracking

Do not create Linear issues, sub-issues, comments, or status updates for work in this project.

Use GitHub pull requests as the source of truth. Do not file leftover work in Linear.

## Codex worktree, Environment, and PR binding

Keep the primary checkout on `main`. Do not implement Candela coding work there, and do not touch dirty files on that checkout.

For a coding task in this repository, bind a Codex `worktree` Environment to the Candela / betterDisplay project before changing code. Do not leave the task on the primary checkout and then isolate only with shell `git worktree add` plus `gh pr create`. That leaves the Environment panel, current branch, Changes, and pull request detached from the running task.

Put an isolated checkout at `<repo-root>/.codex/worktrees/<branch-or-task-slug>`. Do not default to a sibling directory next to the repo, and do not treat `/Users/wyman/.codex/worktrees` as the default location.

A running task cannot be rebound later. If the work must land on a branch, worktree, and pull request, first create or fork a Codex-bound `worktree` task, then implement in that task. Do not try to repair an unbound running task with per-command working-directory overrides.

The goal is that Environment, the current branch, Changes, and the pull request all belong to the same task.

This project still does not create Linear issues. GitHub pull requests remain the source of truth. Do not merge into `main` unless the user explicitly asks to merge.
