#!/usr/bin/env bash
#
# Layer 2: Setup integration tests
# Run setup-rlcr-loop.sh and verify state.md contains correct base_commit
# and setup_diff_size_warning fields.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup-rlcr-loop.sh"

echo "=========================================="
echo "Diff Size Guard - Setup Integration Tests"
echo "=========================================="
echo ""

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "FATAL: setup-rlcr-loop.sh not found at $SETUP_SCRIPT" >&2
    exit 1
fi

# Helper: ensure default branch is named "main" after init_test_git_repo
ensure_main_branch() {
    local dir="$1"
    git -C "$dir" branch -m main 2>/dev/null || true
}

# Helper: extract a YAML field from state.md frontmatter
extract_state_field() {
    local state_file="$1"
    local field="$2"
    grep "^${field}:" "$state_file" | sed "s/${field}: *//" | head -1
}

# T1: setup writes merge-base (not rev-parse) to state.md
setup_test_dir
repo_dir="$TEST_DIR/test-setup-mergebase"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"

# Diverge feature from main, then advance main
git checkout -q -b feature
echo "feature" > f.txt
git add f.txt
git commit -q -m "Feature work"
git checkout -q main
echo "main-advance" > m.txt
git add m.txt
git commit -q -m "Main advances"
git checkout -q feature

expected_merge_base=$(git merge-base HEAD main)
main_tip=$(git rev-parse main)

# Create a minimal plan file
echo -e "# Plan\n\nline2\nline3\nline4\nline5\nline6" > plan.md
git add plan.md
git commit -q -m "Add plan"

# Run setup (skip-impl to avoid needing full plan structure)
setup_stderr="$TEST_DIR/setup-stderr.log"
if CLAUDE_PROJECT_DIR="$repo_dir" bash "$SETUP_SCRIPT" --skip-impl --max 1 --base-branch main 2>"$setup_stderr"; then
    # Find the state.md
    state_file=$(find .humanize/rlcr -name "state.md" 2>/dev/null | head -1)
    if [[ -n "$state_file" ]]; then
        actual_base=$(extract_state_field "$state_file" "base_commit")
        if [[ "$actual_base" == "$expected_merge_base" ]]; then
            pass "T1: state.md base_commit matches merge-base"
        else
            fail "T1: state.md base_commit matches merge-base" "$expected_merge_base" "$actual_base"
        fi
        if [[ "$actual_base" != "$main_tip" ]]; then
            pass "T1b: state.md base_commit is NOT main tip"
        else
            fail "T1b: state.md base_commit is NOT main tip" "!= $main_tip" "$actual_base"
        fi
    else
        fail "T1: state.md not found after setup" "state.md exists" "not found"
    fi
else
    fail "T1: setup-rlcr-loop.sh exited non-zero" "exit 0" "exit $?"
    cat "$setup_stderr" >&2
fi

cd "$SCRIPT_DIR"

# T2: setup warning fires when diff exceeds tiny threshold
setup_test_dir
repo_dir="$TEST_DIR/test-setup-warning"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"

git checkout -q -b feature
for i in $(seq 1 30); do
    echo "line $i of large change with enough content to exceed 100 byte threshold for testing" >> large.txt
done
git add large.txt
git commit -q -m "Large change"

echo -e "# Plan\n\nline2\nline3\nline4\nline5\nline6" > plan.md
git add plan.md
git commit -q -m "Add plan"

# Set tiny threshold via project config
mkdir -p .humanize
printf '{"max_review_diff_chars": 100}' > .humanize/config.json

setup_stderr="$TEST_DIR/setup-warning-stderr.log"
setup_status=0
CLAUDE_PROJECT_DIR="$repo_dir" bash "$SETUP_SCRIPT" --skip-impl --max 1 --base-branch main 2>"$setup_stderr" || setup_status=$?

if [[ "$setup_status" -ne 0 ]]; then
    fail "T2: setup should succeed even with large diff (warning, not abort)" "exit 0" "exit $setup_status; stderr=$(tail -5 "$setup_stderr")"
fi

if grep -q "WARNING: Review diff is large" "$setup_stderr"; then
    pass "T2: setup prints WARNING when diff exceeds threshold"
else
    fail "T2: setup prints WARNING when diff exceeds threshold" "WARNING in stderr" "not found"
fi

state_file=$(find .humanize/rlcr -name "state.md" 2>/dev/null | head -1 || true)
if [[ -n "$state_file" ]]; then
    warning_val=$(extract_state_field "$state_file" "setup_diff_size_warning")
    if [[ "$warning_val" == "true" ]]; then
        pass "T2b: state.md setup_diff_size_warning is true"
    else
        fail "T2b: state.md setup_diff_size_warning is true" "true" "$warning_val"
    fi
fi

cd "$SCRIPT_DIR"

# T3: setup does NOT warn when diff is below threshold
setup_test_dir
repo_dir="$TEST_DIR/test-setup-no-warning"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"

git checkout -q -b feature
echo "tiny" > tiny.txt
git add tiny.txt
git commit -q -m "Tiny change"

echo -e "# Plan\n\nline2\nline3\nline4\nline5\nline6" > plan.md
git add plan.md
git commit -q -m "Add plan"

setup_stderr="$TEST_DIR/setup-nowarning-stderr.log"
setup_status=0
CLAUDE_PROJECT_DIR="$repo_dir" bash "$SETUP_SCRIPT" --skip-impl --max 1 --base-branch main 2>"$setup_stderr" || setup_status=$?

if [[ "$setup_status" -ne 0 ]]; then
    fail "T3: setup should succeed for tiny diff" "exit 0" "exit $setup_status; stderr=$(tail -5 "$setup_stderr")"
fi

if grep -q "WARNING: Review diff is large" "$setup_stderr"; then
    fail "T3: setup should NOT warn for tiny diff" "no WARNING" "WARNING found"
else
    pass "T3: setup does not warn for tiny diff"
fi

state_file=$(find .humanize/rlcr -name "state.md" 2>/dev/null | head -1 || true)
if [[ -n "$state_file" ]]; then
    warning_val=$(extract_state_field "$state_file" "setup_diff_size_warning")
    if [[ "$warning_val" == "false" ]]; then
        pass "T3b: state.md setup_diff_size_warning is false"
    else
        fail "T3b: state.md setup_diff_size_warning is false" "false" "$warning_val"
    fi
fi

cd "$SCRIPT_DIR"

# T4: setup fails clearly for orphan branches (no common ancestor)
setup_test_dir
repo_dir="$TEST_DIR/test-setup-orphan"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"

git checkout -q --orphan orphan-branch
git rm -rf . 2>/dev/null || true
echo "orphan" > orphan.txt
git add orphan.txt
git commit -q -m "Orphan commit"

echo -e "# Plan\n\nline2\nline3\nline4\nline5\nline6" > plan.md
git add plan.md
git commit -q -m "Add plan"

setup_stderr="$TEST_DIR/setup-orphan-stderr.log"
if CLAUDE_PROJECT_DIR="$repo_dir" bash "$SETUP_SCRIPT" --skip-impl --max 1 --base-branch main 2>"$setup_stderr"; then
    fail "T4: setup should fail for orphan branch" "non-zero exit" "exit 0"
else
    if grep -q "No common ancestor" "$setup_stderr"; then
        pass "T4: setup fails with 'No common ancestor' for orphan branch"
    else
        fail "T4: setup fails with 'No common ancestor'" "error message" "$(tail -3 "$setup_stderr")"
    fi
fi

cd "$SCRIPT_DIR"

print_test_summary "Diff Size Guard - Setup Integration Tests"
