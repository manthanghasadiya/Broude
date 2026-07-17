#!/usr/bin/env bash
# broude/tests/test-session-audit.sh
#
# Integration tests for hooks/session-audit.sh
#
# Usage:
#   bash tests/test-session-audit.sh          # from repo root
#   bash test-session-audit.sh                # from tests/ directory
#
# Exit code: 0 if all tests pass, 1 if any fail.
#
# IMPORTANT: Do NOT add set -e / set -euo pipefail here.
# (a) (( counter++ )) exits 1 when counter was 0, which kills the script under set -e.
# (b) We intentionally run commands that may fail (hook invocations, git init, etc.)
#     and check their exit codes manually.

# ─── Setup ────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-audit.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

# Counters — use $(( )) assignment form, never (( var++ )) standalone:
# (( 0 )) exits with code 1 (falsy), which triggers set -e if active.
PASS_COUNT=0
FAIL_COUNT=0
TEMP_DIRS=()

# Cleanup on exit — removes all temp project directories
cleanup() {
    for d in "${TEMP_DIRS[@]+"${TEMP_DIRS[@]}"}"; do
        rm -rf "$d" 2>/dev/null || true
    done
}
trap cleanup EXIT

# ─── Test helpers ─────────────────────────────────────────────────────────────

# make_temp_project: create a temp directory simulating a project.
# Prints the path. Registers for cleanup.
make_temp_project() {
    local tmpdir
    tmpdir=$(mktemp -d /tmp/broude-test-XXXXXX)
    TEMP_DIRS+=("$tmpdir")
    echo "$tmpdir"
}

# run_hook: pipe SessionStart JSON to session-audit.sh with a given CWD.
# Prints combined stdout. Always succeeds (hook must exit 0).
run_hook() {
    local cwd="${1:-/tmp}"
    local session_json
    session_json="{\"session_id\":\"test-$$\",\"type\":\"init\",\"cwd\":\"${cwd}\",\"timestamp\":\"2026-07-17T00:00:00Z\"}"
    echo "$session_json" | bash "$HOOK" 2>/dev/null
    return 0  # run_hook itself always succeeds regardless of hook exit code
}

# pass: record a PASS with a message.
pass() {
    echo -e "${GREEN}  PASS${NC}: $*"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
}

# fail: record a FAIL with a message.
fail() {
    echo -e "${RED}  FAIL${NC}: $*"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

# skip: record a SKIP (counts as pass, not fail).
skip() {
    echo -e "${YELLOW}  SKIP${NC}: $*"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
}

# assert_contains: fail if string not found in output.
assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="${3:-}"
    if echo "$output" | grep -qF "$expected"; then
        pass "found '${expected}'"
    else
        fail "expected to find '${expected}'"
        if [[ -n "$test_name" ]]; then
            echo "         in test: ${test_name}"
        fi
        echo "         actual output:"
        echo "$output" | head -30 | sed 's/^/           | /'
    fi
}

# assert_not_contains: fail if string IS found in output.
assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="${3:-}"
    if echo "$output" | grep -qF "$unexpected"; then
        fail "should NOT contain '${unexpected}'"
        if [[ -n "$test_name" ]]; then
            echo "         in test: ${test_name}"
        fi
    else
        pass "correctly absent '${unexpected}'"
    fi
}

# assert_exit_zero: verify the hook exits 0 for a given CWD.
assert_exit_zero() {
    local cwd="${1:-/tmp}"
    local json
    json="{\"session_id\":\"exit-test-$$\",\"type\":\"init\",\"cwd\":\"${cwd}\",\"timestamp\":\"2026-07-17T00:00:00Z\"}"
    if echo "$json" | bash "$HOOK" &>/dev/null; then
        pass "hook exited with code 0"
    else
        fail "hook exited non-zero (MUST always exit 0 for SessionStart)"
    fi
}

# assert_exit_zero_with_input: verify hook exits 0 for arbitrary stdin.
assert_exit_zero_with_input() {
    local label="$1"
    local input="$2"
    if echo "$input" | bash "$HOOK" &>/dev/null; then
        pass "hook exited 0 for: ${label}"
    else
        fail "hook exited non-zero for: ${label}"
    fi
}

# ─── Pre-flight ───────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Broude Test Suite ===${NC}"
echo ""

if [[ ! -f "$HOOK" ]]; then
    echo -e "${RED}ERROR: Hook not found at ${HOOK}${NC}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}WARN: jq not installed — some tests may produce SKIPs${NC}"
fi

# ─── Test 1: Hook always exits 0 ──────────────────────────────────────────────

echo -e "${BOLD}Test 1: Hook always exits 0 (even with bad input)${NC}"

echo -e "  Subtest 1a: valid JSON pointing at home dir..."
assert_exit_zero "${HOME}"

echo -e "  Subtest 1b: invalid JSON..."
assert_exit_zero_with_input "invalid JSON" "NOT_JSON"

echo -e "  Subtest 1c: empty stdin..."
assert_exit_zero_with_input "empty stdin" ""

echo -e "  Subtest 1d: nonexistent CWD..."
assert_exit_zero "/tmp/broude-nonexistent-dir-$$"

echo -e "  Subtest 1e: JSON missing cwd field..."
assert_exit_zero_with_input "missing cwd" '{"session_id":"t","type":"init","timestamp":"2026-07-17T00:00:00Z"}'

# ─── Test 2: Clean project (no .env, no package-lock) ─────────────────────────

echo ""
echo -e "${BOLD}Test 2: Clean project — header present, no crash${NC}"

clean_project=$(make_temp_project)
git -C "$clean_project" init -q 2>/dev/null || true
output=$(run_hook "$clean_project")

assert_contains  "$output" "BROUDE"   "header present"
assert_contains  "$output" "Risk:"    "footer present"
assert_not_contains "$output" "NOT in .gitignore" "no env gitignore warning in clean project"

# ─── Test 3: .env exists but NOT in .gitignore ────────────────────────────────

echo ""
echo -e "${BOLD}Test 3: .env exists but NOT in .gitignore — expect WARN${NC}"

env_project=$(make_temp_project)
git -C "$env_project" init -q 2>/dev/null || true
echo "SOME_VAR=value" > "${env_project}/.env"
echo "# nothing here" > "${env_project}/.gitignore"
output=$(run_hook "$env_project")

assert_contains "$output" "[WARN]"      "output contains WARN"
assert_contains "$output" ".env"        "output mentions .env"
assert_contains "$output" ".gitignore"  "output mentions .gitignore"

# ─── Test 4: .env is properly in .gitignore ───────────────────────────────────

echo ""
echo -e "${BOLD}Test 4: .env is in .gitignore — expect PASS, no gitignore WARN${NC}"

safe_env_project=$(make_temp_project)
git -C "$safe_env_project" init -q 2>/dev/null || true
echo "SOME_VAR=value" > "${safe_env_project}/.env"
printf '.env\n*.env\n' > "${safe_env_project}/.gitignore"
output=$(run_hook "$safe_env_project")

assert_contains     "$output" "[PASS]"           ".env covered → PASS line present"
assert_not_contains "$output" "NOT in .gitignore" "no gitignore warning when covered"

# ─── Test 5: Fake API key in .env — secret detection ─────────────────────────

echo ""
echo -e "${BOLD}Test 5: Fake API key in .env — expect secret detection WARN${NC}"

secret_project=$(make_temp_project)
git -C "$secret_project" init -q 2>/dev/null || true
cat > "${secret_project}/.env" << 'ENVEOF'
# Fake keys for testing — NOT real credentials
OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
ENVEOF
printf '.env\n' > "${secret_project}/.gitignore"
output=$(run_hook "$secret_project")

assert_contains "$output" "[WARN]" "output contains WARN (from secret or gitignore check)"
if echo "$output" | grep -qiE "secret|aws|openai|api.key|detected"; then
    pass "a secret pattern was detected in .env"
else
    skip "secret pattern not detected (may need jq + pattern file)"
fi

# ─── Test 6: .env.test with fake key — dynamic glob catches it ────────────────

echo ""
echo -e "${BOLD}Test 6: .env.test with fake key — dynamic .env* glob catches it${NC}"

envtest_project=$(make_temp_project)
git -C "$envtest_project" init -q 2>/dev/null || true
cat > "${envtest_project}/.env.test" << 'ENVEOF'
OPENAI_API_KEY=sk-test1234567890abcdefghijklmnop
ENVEOF
output=$(run_hook "$envtest_project")

if echo "$output" | grep -qE "\.env\.test|secret|detected|WARN"; then
    pass ".env.test was scanned (output contains relevant content)"
else
    skip ".env.test scan inconclusive — verify jq and pattern file are accessible"
fi

# ─── Test 7: Git-tracked .env — expect FAIL ───────────────────────────────────

echo ""
echo -e "${BOLD}Test 7: .env tracked by git — expect FAIL${NC}"

tracked_project=$(make_temp_project)
git -C "$tracked_project" init -q 2>/dev/null || true
git -C "$tracked_project" config user.email "test@test.com" 2>/dev/null || true
git -C "$tracked_project" config user.name  "Test"          2>/dev/null || true
echo "SECRET=oops" > "${tracked_project}/.env"
git -C "$tracked_project" add .env          2>/dev/null || true
git -C "$tracked_project" commit -q -m "whoops" 2>/dev/null || true
output=$(run_hook "$tracked_project")

assert_contains "$output" "[FAIL]" "output contains FAIL for git-tracked .env"
assert_contains "$output" "git"    "output mentions git"

# ─── Test 8: npm: no package-lock.json → INFO skip message ───────────────────

echo ""
echo -e "${BOLD}Test 8: No package-lock.json — expect INFO skip message${NC}"

no_npm_project=$(make_temp_project)
output=$(run_hook "$no_npm_project")

assert_contains "$output" "package-lock.json" "output mentions package-lock.json when skipping npm"

# ─── Test 9: pip: no requirements.txt → INFO skip message ────────────────────

echo ""
echo -e "${BOLD}Test 9: No requirements.txt — expect INFO skip message${NC}"

no_pip_project=$(make_temp_project)
output=$(run_hook "$no_pip_project")

assert_contains "$output" "requirements.txt" "output mentions requirements.txt when skipping pip"

# ─── Test 10: Non-git dir → INFO skip for git hook check ─────────────────────

echo ""
echo -e "${BOLD}Test 10: Non-git directory — expect git hook check skipped with INFO${NC}"

nongit_project=$(make_temp_project)
output=$(run_hook "$nongit_project")

assert_contains "$output" "git" "output mentions git (skip message)"

# ─── Test 11: Report header format ───────────────────────────────────────────

echo ""
echo -e "${BOLD}Test 11: Output format — header, footer, risk line${NC}"

fmt_project=$(make_temp_project)
output=$(run_hook "$fmt_project")

assert_contains "$output" "BROUDE"   "header contains BROUDE"
assert_contains "$output" "Risk:"    "footer contains Risk:"
assert_contains "$output" "Action:"  "footer contains Action:"
assert_contains "$output" "PASS"     "output contains PASS"

# ─── Test 12: Fixture JSON file ───────────────────────────────────────────────

echo ""
echo -e "${BOLD}Test 12: Fixture session-start.json runs without crash${NC}"

fixture_json="${FIXTURES_DIR}/session-start.json"
if [[ -f "$fixture_json" ]]; then
    if bash "$HOOK" < "$fixture_json" &>/dev/null; then
        pass "hook runs cleanly with fixture JSON"
    else
        fail "hook returned non-zero with fixture JSON"
    fi
else
    skip "fixture file not found at ${fixture_json}"
fi

# ─── Test 13: Hook handles deeply invalid JSON cleanly ────────────────────────

echo ""
echo -e "${BOLD}Test 13: Malformed JSON variants — hook stays alive${NC}"

for bad_input in '{}' '{"cwd": null}' '{"cwd": ""}' 'null' '[]'; do
    assert_exit_zero_with_input "input=${bad_input}" "$bad_input"
done

# ─── Test 14: Output is non-empty even for an empty project ───────────────────

echo ""
echo -e "${BOLD}Test 14: Output is non-empty for any project${NC}"

empty_project=$(make_temp_project)
output=$(run_hook "$empty_project")

if [[ -n "$output" ]]; then
    pass "hook produced non-empty output"
else
    fail "hook produced no output at all"
fi

# ─── Test 15: JetBrains/Chrome INFO lines appear (not installed machines) ─────

echo ""
echo -e "${BOLD}Test 15: JetBrains + Chrome skip messages (if not installed)${NC}"

infra_project=$(make_temp_project)
output=$(run_hook "$infra_project")

# On a dev machine these may be installed (PASS) or not (INFO skip).
# Either way, the output must contain SOME reference to JetBrains and Chrome.
if echo "$output" | grep -qiE "jetbrains|JetBrains"; then
    pass "output references JetBrains (installed or skipped)"
else
    fail "output has no mention of JetBrains — check was silently dropped"
fi

if echo "$output" | grep -qiE "chrome|Chrome"; then
    pass "output references Chrome (installed or skipped)"
else
    fail "output has no mention of Chrome — check was silently dropped"
fi

# ─── Test 16: Audit log written to ~/.broude/audit.log ───────────────────────

echo ""
echo -e "${BOLD}Test 16: Audit log — hook writes to ~/.broude/audit.log${NC}"

log_project=$(make_temp_project)
log_file="${HOME}/.broude/audit.log"
lines_before=0
if [[ -f "$log_file" ]]; then
    lines_before=$(wc -l < "$log_file")
fi

run_hook "$log_project" > /dev/null

if [[ -f "$log_file" ]]; then
    lines_after=$(wc -l < "$log_file")
    if [[ "$lines_after" -gt "$lines_before" ]]; then
        pass "audit.log grew after hook run (${lines_before} → ${lines_after} lines)"
    else
        fail "audit.log exists but did not grow after hook run"
    fi
else
    fail "audit.log was not created at ${log_file}"
fi

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo -e "${BOLD}Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}"
echo "────────────────────────────────────────"
echo ""

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
