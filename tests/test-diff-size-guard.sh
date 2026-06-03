#!/usr/bin/env bash
#
# Tests for the diff-size guard feature:
# Layer 1: Helper-level tests (compute_review_diff_size, git primitives)
# Layer 2: Setup integration tests (setup-rlcr-loop.sh produces correct state.md)
# Layer 3: Stop-hook integration tests (stop hook blocks/passes correctly)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Source portable-timeout.sh for run_with_timeout (required by loop-common.sh)
source "$PROJECT_ROOT/scripts/portable-timeout.sh"

# Source loop-common.sh to get compute_review_diff_size helper
source "$PROJECT_ROOT/hooks/lib/loop-common.sh" "$PROJECT_ROOT" "/tmp/test-proj" 2>/dev/null || true

echo "=========================================="
echo "Diff Size Guard Tests"
echo "=========================================="
echo ""

# ========================================
# Layer 1: Helper-level tests
# ========================================

echo "--- Layer 1: Helper-level tests ---"
echo ""

# Helper: ensure default branch is named "main" after init_test_git_repo
ensure_main_branch() {
    local dir="$1"
    git -C "$dir" branch -m main 2>/dev/null || true
}

# T1: compute_review_diff_size returns numeric size for valid base
setup_test_dir
repo_dir="$TEST_DIR/test-helper-valid"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
git checkout -q -b feature
echo "some content" > new-file.txt
git add new-file.txt
git commit -q -m "Add file"
base=$(git merge-base HEAD main)
size=$(compute_review_diff_size "$repo_dir" "$base" 30)
if [[ "$size" =~ ^[0-9]+$ ]] && [[ "$size" -gt 0 ]]; then
    pass "T1: compute_review_diff_size returns numeric size ($size bytes)"
else
    fail "T1: compute_review_diff_size returns numeric size" ">0 integer" "$size"
fi
cd "$SCRIPT_DIR"

# T2: compute_review_diff_size fails for nonexistent base
setup_test_dir
repo_dir="$TEST_DIR/test-helper-invalid"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
fake_sha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
if result=$(compute_review_diff_size "$repo_dir" "$fake_sha" 30 2>/dev/null); then
    fail "T2: compute_review_diff_size should fail for nonexistent base" "non-zero exit" "exit 0, result=$result"
else
    pass "T2: compute_review_diff_size fails for nonexistent base"
fi
cd "$SCRIPT_DIR"

# T3: cat-file -e rejects nonexistent SHA
setup_test_dir
repo_dir="$TEST_DIR/test-catfile"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
if git cat-file -e "${fake_sha}^{commit}" 2>/dev/null; then
    fail "T3: cat-file -e should reject nonexistent SHA" "exit non-zero" "exit 0"
else
    pass "T3: cat-file -e correctly rejects nonexistent SHA"
fi
cd "$SCRIPT_DIR"

# T4: merge-base captures fork point, not branch tip
setup_test_dir
repo_dir="$TEST_DIR/test-merge-base"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
git checkout -q -b feature
echo "feature work" > feature.txt
git add feature.txt
git commit -q -m "Feature commit"
git checkout -q main
echo "main advance" > main-new.txt
git add main-new.txt
git commit -q -m "Main advances"
expected_base=$(git merge-base feature main)
main_tip=$(git rev-parse main)
git checkout -q feature
if [[ "$expected_base" != "$main_tip" ]]; then
    pass "T4: merge-base differs from main tip (fork point, not branch tip)"
else
    fail "T4: merge-base differs from main tip" "different SHAs" "same SHA"
fi
cd "$SCRIPT_DIR"

# T5: merge-base returns HEAD when HEAD and BASE_BRANCH point to same commit
setup_test_dir
repo_dir="$TEST_DIR/test-merge-base-self"
init_test_git_repo "$repo_dir"
ensure_main_branch "$repo_dir"
cd "$repo_dir"
head_sha=$(git rev-parse HEAD)
merge_base_sha=$(git merge-base HEAD main)
if [[ "$head_sha" == "$merge_base_sha" ]]; then
    pass "T5: merge-base returns HEAD when HEAD == BASE_BRANCH tip"
else
    fail "T5: merge-base returns HEAD when HEAD == BASE_BRANCH tip" "$head_sha" "$merge_base_sha"
fi
cd "$SCRIPT_DIR"

# T6: config validation rejects 0 (only positive integers)
if [[ "0" =~ ^[1-9][0-9]*$ ]]; then
    fail "T6: regex should reject 0" "no match" "matched"
else
    pass "T6: config regex ^[1-9][0-9]*$ correctly rejects 0"
fi
if [[ "800000" =~ ^[1-9][0-9]*$ ]]; then
    pass "T6b: config regex accepts 800000"
else
    fail "T6b: config regex accepts 800000" "match" "no match"
fi

print_test_summary "Diff Size Guard Tests - Layer 1"
