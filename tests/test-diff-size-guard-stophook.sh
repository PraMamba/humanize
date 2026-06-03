#!/usr/bin/env bash
#
# Layer 3: Stop-hook integration tests
# Construct state.md + mock codex + tiny threshold, run stop hook,
# verify block/pass behavior.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

STOP_HOOK="$PROJECT_ROOT/hooks/loop-codex-stop-hook.sh"

echo "=========================================="
echo "Diff Size Guard - Stop-Hook Integration Tests"
echo "=========================================="
echo ""

if [[ ! -f "$STOP_HOOK" ]]; then
    echo "FATAL: stop hook not found at $STOP_HOOK" >&2
    exit 1
fi

# Helper: ensure default branch is named "main" after init_test_git_repo
ensure_main_branch() {
    local dir="$1"
    git -C "$dir" branch -m main 2>/dev/null || true
}

# Helper: create a complete stop hook fixture for review-phase testing
# Mirrors the pattern from test-stop-hook-legacy-compat.sh but with
# review_started=true and .review-phase-started marker for the code review path.
create_review_fixture() {
    local repo_dir="$1"
    local base_commit="$2"
    local base_branch="${3:-main}"
    local max_diff="${4:-800000}"
    local branch

    branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)
    local loop_dir="$repo_dir/.humanize/rlcr/2026-06-03_test"
    mkdir -p "$loop_dir"

    # Plan file (required by stop hook)
    cat > "$loop_dir/plan.md" << 'PLANEOF'
# Test Plan

Diff size guard test plan.
PLANEOF

    # State file - review_started=true to reach code review path
    cat > "$loop_dir/state.md" << EOF
---
current_round: 1
max_iterations: 42
codex_model: gpt-5.5
codex_effort: high
codex_timeout: 60
push_every_round: false
full_review_round: 5
plan_file: plan.md
plan_tracked: false
start_branch: $branch
base_branch: $base_branch
base_commit: $base_commit
review_started: true
ask_codex_question: true
session_id:
agent_teams: false
privacy_mode: false
bitlesson_required: false
bitlesson_file: .humanize/bitlesson.md
bitlesson_allow_empty_none: true
mainline_stall_count: 0
last_mainline_verdict: unknown
drift_status: normal
setup_diff_size_warning: false
setup_diff_chars: 0
setup_diff_files: 0
setup_diff_commits: 0
max_review_diff_chars: $max_diff
started_at: 2026-06-03T10:00:00Z
---
EOF

    # Review phase marker (required when review_started=true)
    echo "build_finish_round=0" > "$loop_dir/.review-phase-started"

    # Summary file for the current round (required by summary check)
    cat > "$loop_dir/round-1-summary.md" << 'SUMEOF'
# Round 1 Summary

Test summary for diff size guard testing.

## BitLesson Delta
Action: none
SUMEOF

    # Goal tracker (required by goal tracker check)
    cat > "$loop_dir/goal-tracker.md" << 'GTEOF'
# Goal Tracker
## IMMUTABLE SECTION
### Ultimate Goal
Test diff size guard.
### Acceptance Criteria
- AC-1: Diff size gate blocks when threshold exceeded.
## MUTABLE SECTION
### Plan Version: 1 (Updated: Round 0)
#### Active Tasks
| Task | Target AC | Status | Notes |
|------|-----------|--------|-------|
| Test diff gate | AC-1 | in-progress | - |
GTEOF

    # Round contract (required by round contract check)
    cat > "$loop_dir/round-1-contract.md" << 'RCEOF'
# Round 1 Contract

## Mainline Objective
Test diff size guard behavior.

## Blocking Items
- Validate diff size gate

## Queued Items
(none)
RCEOF
}

# Setup mock codex in PATH
setup_mock_codex() {
    local mock_dir="$1"
    local marker_file="$2"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/codex" << 'MOCK_EOF'
#!/usr/bin/env bash
# Only record marker for actual review/exec invocations, not --help or features
case "$1" in
    review|exec)
        echo "CODEX_INVOKED" > "$MOCK_MARKER_FILE"
        echo "No issues found."
        echo "COMPLETE"
        ;;
    features)
        echo ""
        ;;
    --help|-h)
        echo "codex mock --disable-hooks"
        ;;
    *)
        echo "mock codex: unknown command $1" >&2
        ;;
esac
exit 0
MOCK_EOF
    chmod +x "$mock_dir/codex"
}

# T1: Stop hook blocks when diff exceeds tiny threshold (codex NOT called)
setup_test_dir
repo_dir="$TEST_DIR/test-hook-blocks"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
git checkout -q -b feature
for i in $(seq 1 20); do
    echo "line $i padding content to exceed the tiny threshold for testing" >> big.txt
done
git add big.txt
git commit -q -m "Big change"

base_commit=$(git merge-base HEAD main)
create_review_fixture "$repo_dir" "$base_commit" "main" "100"

# Mock codex
mock_dir="$TEST_DIR/mock-bin"
marker_file="$TEST_DIR/codex-was-called"
setup_mock_codex "$mock_dir" "$marker_file"
rm -f "$marker_file"

# Run stop hook with mock codex on PATH
set +e
hook_output=$(
    cd "$repo_dir"
    CLAUDE_PROJECT_DIR="$repo_dir" \
    DEFAULT_MAX_REVIEW_DIFF_CHARS=100 \
    MOCK_MARKER_FILE="$marker_file" \
    PATH="$mock_dir:$PATH" \
    "$STOP_HOOK" <<< '{}' 2>/dev/null
)
hook_exit=$?
set -e

if echo "$hook_output" | grep -q '"decision"'; then
    if echo "$hook_output" | grep -q '"block"'; then
        pass "T1: stop hook outputs decision:block when diff exceeds threshold"
    else
        fail "T1: stop hook outputs decision:block" "block" "$hook_output"
    fi
else
    fail "T1: stop hook outputs decision:block" "JSON with decision" "$hook_output"
fi

if [[ ! -f "$marker_file" ]]; then
    pass "T1b: codex was NOT called when diff exceeded threshold"
else
    fail "T1b: codex was NOT called" "marker absent" "marker present"
fi

if echo "$hook_output" | grep -q "deterministic\|Do not retry"; then
    pass "T1c: block message contains deterministic/no-retry language"
else
    fail "T1c: block message contains deterministic/no-retry language" "present" "not found in: $(echo "$hook_output" | head -5)"
fi

cd "$SCRIPT_DIR"

# T2: Stop hook blocks for invalid (nonexistent) base commit
setup_test_dir
repo_dir="$TEST_DIR/test-hook-invalid-base"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
git checkout -q -b feature
echo "change" > file2.txt
git add file2.txt
git commit -q -m "Change"

fake_sha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
create_review_fixture "$repo_dir" "$fake_sha" "main"

mock_dir="$TEST_DIR/mock-bin2"
marker_file="$TEST_DIR/codex-was-called-2"
setup_mock_codex "$mock_dir" "$marker_file"
rm -f "$marker_file"

set +e
hook_output=$(
    cd "$repo_dir"
    CLAUDE_PROJECT_DIR="$repo_dir" \
    MOCK_MARKER_FILE="$marker_file" \
    PATH="$mock_dir:$PATH" \
    "$STOP_HOOK" <<< '{}' 2>/dev/null
)
set -e

if echo "$hook_output" | grep -q '"block"'; then
    pass "T2: stop hook blocks for nonexistent base commit"
else
    fail "T2: stop hook blocks for nonexistent base commit" "decision:block" "$hook_output"
fi

if [[ ! -f "$marker_file" ]]; then
    pass "T2b: codex was NOT called for invalid base"
else
    fail "T2b: codex was NOT called" "marker absent" "marker present"
fi

cd "$SCRIPT_DIR"

# T3: Stop hook passes when diff is below threshold (codex IS called)
setup_test_dir
repo_dir="$TEST_DIR/test-hook-passes"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
git checkout -q -b feature
echo "x" > tiny.txt
git add tiny.txt
git commit -q -m "Tiny"

base_commit=$(git merge-base HEAD main)
create_review_fixture "$repo_dir" "$base_commit" "main" "999999999"

mock_dir="$TEST_DIR/mock-bin3"
marker_file="$TEST_DIR/codex-was-called-3"
setup_mock_codex "$mock_dir" "$marker_file"
rm -f "$marker_file"

set +e
hook_output=$(
    cd "$repo_dir"
    CLAUDE_PROJECT_DIR="$repo_dir" \
    DEFAULT_MAX_REVIEW_DIFF_CHARS=999999999 \
    MOCK_MARKER_FILE="$marker_file" \
    PATH="$mock_dir:$PATH" \
    "$STOP_HOOK" <<< '{}' 2>/dev/null
)
set -e

if [[ -f "$marker_file" ]]; then
    pass "T3: codex WAS called when diff is below threshold"
else
    # If codex wasn't called, check if the hook blocked for another reason
    if echo "$hook_output" | grep -q '"block"'; then
        fail "T3: codex WAS called when diff is below threshold" "marker present" "hook blocked: $(echo "$hook_output" | head -3)"
    else
        fail "T3: codex WAS called when diff is below threshold" "marker present" "marker absent, output: $(echo "$hook_output" | head -3)"
    fi
fi

cd "$SCRIPT_DIR"

print_test_summary "Diff Size Guard - Stop-Hook Integration Tests"
