# Invalid Review Base Commit

The stored base commit `{{REVIEW_BASE}}` does not exist in this repository or is not an ancestor of HEAD.

## What Happened

This can happen when:
- The base branch was force-pushed after the loop started
- The repository is a shallow clone missing older history
- The state file was manually edited with an invalid SHA

## Important

**This block is deterministic and will repeat until the base commit is corrected. Do not retry without user action.**

## Required Action

Cancel this loop and restart with a valid `--base-branch`.

To cancel: `/humanize:cancel-rlcr-loop`
