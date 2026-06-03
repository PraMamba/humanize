# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Humanize is a Claude Code plugin that provides iterative development with independent AI review. The core workflow is **RLCR** (Ralph-Loop with Codex Review): Claude implements a plan, Codex independently reviews the work, and issues feed back into the next implementation round until all acceptance criteria are met.

## Commands

- **Run all tests**: `./tests/run-all-tests.sh` (parallel by default; `HUMANIZE_TEST_JOBS=1` for serial)
- **Run a single test**: `bash tests/test-<name>.sh`
- **Check shell syntax**: `bash -n path/to/script.sh` (CI also runs `zsh -n` on all `.sh` files)
- **Preview Codex skill install**: `./scripts/install-skill.sh --target codex --dry-run`

CI requires `bash`, `zsh`, `jq`, `git`, and Python 3.

## Architecture

### Plugin System

The plugin is packaged as a Claude Code plugin (`.claude-plugin/plugin.json` and `marketplace.json`). Skills in `skills/` are the entrypoints Claude Code loads. Commands in `commands/` define slash-command specs (gen-plan, gen-idea, refine-plan, start-rlcr-loop, cancel-rlcr-loop).

### Hook Lifecycle

The RLCR loop is driven by Claude Code hooks defined in `hooks/hooks.json`:
- **PreToolUse hooks** (`loop-*-validator.sh`) intercept Write, Edit, Read, and Bash calls to enforce plan-file protection, path validation, and state-file safety during a loop.
- **PostToolUse hook** (`loop-post-bash-hook.sh`) runs after Bash calls.
- **Stop hook** (`loop-codex-stop-hook.sh`) is the core loop driver. When Claude tries to stop, this hook invokes Codex to review the work. If Codex does not confirm completion, the hook blocks the exit and feeds review feedback back to Claude for another round.
- **UserPromptSubmit hook** (`loop-plan-file-validator.sh`) validates plan state on each user prompt.

All hooks source shared libraries from `hooks/lib/`:
- `loop-common.sh` — state field constants, shared functions used by every hook and setup/cancel scripts
- `template-loader.sh` — loads and renders `{{VAR}}` templates from `prompt-template/`
- `project-root.sh` — resolves the user's project root
- `methodology-analysis.sh` — methodology scoring for reviews

### Prompt Templates

`prompt-template/` contains all prompt text, organized by audience:
- `block/` — error/block messages shown when hooks reject an action
- `claude/` — prompts injected into Claude's context (next-round, finalize, drift-replan)
- `codex/` — prompts sent to Codex for reviews (code-review-phase, full-alignment-review)
- `plan/` — plan generation and refinement templates
- `idea/` — idea generation templates

Templates use `{{VARIABLE_NAME}}` placeholders, rendered by `template-loader.sh`.

### Configuration Hierarchy

Config is loaded by `scripts/lib/config-loader.sh` with a layered merge:
1. `config/default_config.json` — plugin defaults (codex_model, codex_effort, bitlesson_model, agent_teams, gen_plan_mode)
2. User project config (`.humanize/config.json`) — per-project overrides
3. Environment variables — highest priority

`scripts/lib/model-router.sh` routes model names to providers (gpt-*/o* to Codex, claude-*/haiku/sonnet/opus to Claude).

### Runtime State

During an RLCR loop, state lives in `.humanize/rlcr/<timestamp>/`:
- `state.md` — current round, max iterations, codex config, branch info
- `round-N-summary.md` — Claude's work summary for round N
- `round-N-review-prompt.md` — prompt sent to Codex
- `round-N-review-result.md` — Codex's review response

### Agents

Agent definitions in `agents/` are used by the plugin as subagents:
- `bitlesson-selector.md` — selects BitLesson entries for tasks
- `draft-relevance-checker.md` — validates draft relevance to the repo
- `plan-compliance-checker.md` — checks plan compliance before RLCR
- `plan-understanding-quiz.md` — generates quiz questions to verify user understands the plan

## Project Rules

- All content (code, comments, tests, docs) must be in English. No emoji or CJK characters.
- Version format is strict `X.Y.Z` (no suffixes like `-alpha`, no dates). When bumping version, update all three locations: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and the `README.md` "Current Version" line.
- `commands/gen-plan.md` (Phase 5 Plan Structure) and `prompt-template/plan/gen-plan-template.md` must stay in sync. Changes to one must be reflected in the other.
- The directions.json schema v1 is defined in two places that must stay in sync: the jq validation expression in `scripts/validate-directions-json.sh` and the schema documentation in `commands/gen-idea.md` (Step 4.5). When adding, removing, or renaming a field in either place, update the other.
- Worker constraints (hard caps, isolation rules, no-push rule, sentinel format) are documented in four places that must stay in sync: `commands/explore-idea.md` (coordinator phases), `prompt-template/explore/worker-prompt.md` (worker instructions), `scripts/validate-explore-idea-io.sh` (cap enforcement), and `docs/usage.md` (user-facing option docs). Any change to a cap value or constraint must be reflected in all four.
- Shell scripts use `#!/usr/bin/env bash`, `set -euo pipefail`, uppercase globals, lowercase locals, hyphenated filenames.
- Tests go in `tests/test-*.sh`; robustness tests in `tests/robustness/test-*-robustness.sh`.

## Branching and PR Rules

- PRs from feature branches must target `dev`. Only `dev` can target `main`. CI enforces this.
- Commit messages use conventional prefixes: `feat(scope):`, `fix(scope):`, `chore:`.
- PRs to `main` trigger a version-bump check that validates all three version files are incremented by exactly +1 (patch, minor, or major).
