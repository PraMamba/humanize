# Review Diff Too Large

The review diff exceeds the configured size limit and Codex review was **not called**.

## Important

**This block is deterministic and will repeat until the review window or configured limit changes. Do not retry the same review without user action.** Ask the user to choose one of the options below.

## Diff Statistics

| Metric | Value |
|--------|-------|
| Base Commit | `{{BASE_COMMIT}}` |
| HEAD | `{{HEAD_COMMIT}}` |
| Base Branch | `{{BASE_BRANCH}}` |
| Commits Since Base | {{COMMITS_SINCE_BASE}} |
| Files Changed | {{FILES_CHANGED}} |
| Diff Size (bytes) | {{DIFF_SIZE_CHARS}} |
| Configured Limit | {{MAX_REVIEW_DIFF_CHARS}} |

## What Happened

The review window ({{DIFF_SIZE_CHARS}} bytes) exceeds the configured limit ({{MAX_REVIEW_DIFF_CHARS}} bytes). Running `codex review` with a diff this large would exceed the Codex input limit and fail.

## Options

1. Cancel and restart with `--base-branch <closer-branch>` to review a narrower range.
2. Split the branch / PR into smaller reviewable chunks.
3. Remove or ignore generated, vendored, lockfile-heavy, or artifact files.
4. Increase `max_review_diff_chars` in `.humanize/config.json` if this is intentional.
5. Rebase only if the current branch relationship is stale or incorrect; it is not a guaranteed size fix.

To cancel the current loop: `/humanize:cancel-rlcr-loop`
