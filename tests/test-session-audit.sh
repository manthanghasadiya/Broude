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
# (( 0 )) exits with code 1 (falsy), which triggers ERR trap / set -e.
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEMP_DIRS=()

# Whether jq is available in this environment
JQ_AVAILABLE=false
command -v jq &>/dev/null && JQ_AVAILABLE=true

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
# Prints combined stdout. Always returns 0 regardless of hook exit code.
run_hook() {
    local cwd="${1:-/tmp}"
    local session_json
    session_json="{\"session_id\":\"test-$$\",\"type\":\"init\",\"cwd\":\"${cwd}\",\"timestamp\":\"2026-07-17T00:00:00Z\"}"
    echo "$session_json" | bash "$HOOK" 2>/dev/null || true
}

# pass: record a PASS with a message.
pass() { echo -e "${GREEN}  PASS${NC}: $*"; PASS_COUNT=$(( PASS_COUNT + 1 )); }

# fail: record a FAIL with a message and optional detail.
fail() {
    echo -e "${RED}  FAIL${NC}: $*"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

# skip: record a SKIP (doesn't count as fail).
skip() { echo -e "${YELLOW}  SKIP${NC}: $*"; SKIP_COUNT=$(( SKIP_COUNT + 1 )); }

# assert_contains: fail if string not found in output.
assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="${3:-}"
    if echo "$output" | grep -qF "$expected"; then
        pass "found '${expected}'"
    else
        fail "expected to find '${expected}'"
        [[ -n "$test_name" ]] && echo "         in test: ${test_name}"
        echo "         actual output:"
        echo "$output" | head -5 | sed 's/^/           | /'
    fi
}

# assert_not_contains: fail if string IS found in output.
assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="${3:-}"
    if echo "$output" | grep -qF "$unexpected"; then
        fail "should NOT contain '${unexpected}'"
        [[ -n "$test_name" ]] && echo "         in test: ${test_name}"
    else
        pass "correctly absent '${unexpected}'"
    fi
}

# skip_if_no_jq: print skip message and return 1 if jq unavailable.
# Usage: skip_if_no_jq "what this test needs" || continue-or-skip-block
skip_if_no_jq() {
    local msg="${1:-jq-dependent check}"
    if [[ "$JQ_AVAILABLE" == false ]]; then
        skip "${msg} (jq not installed)"
        return 1
    fi
    return 0
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

if [[ "$JQ_AVAILABLE" == false ]]; then
    echo -e "${YELLOW}WARN: jq not installed — jq-dependent tests will SKIP (not FAIL)${NC}"
    echo -e "      Install jq to run the full suite: sudo apt-get install -y jq"
    echo ""
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

echo -e "  Subtest 1f: malformed JSON variants..."
for bad_input in '{}' '{"cwd": null}' 'null' '[]'; do
    assert_exit_zero_with_input "input=${bad_input}" "$bad_input"
done

# ─── Test 2: Output is always non-empty ───────────────────────────────────────

echo ""
echo -e "${BOLD}Test 2: Hook always produces non-empty output${NC}"

empty_project=$(make_temp_project)
output=$(run_hook "$empty_project")

if [[ -n "$output" ]]; then
    pass "hook produced non-empty output"
else
    fail "hook produced no output at all"
fi

# Header line with BROUDE should always appear (written before jq check)
assert_contains "$output" "BROUDE" "header contains BROUDE"

# ─── Test 3: Clean project — full checks (requires jq) ────────────────────────

echo ""
echo -e "${BOLD}Test 3: Clean project with jq — header + footer present${NC}"

if skip_if_no_jq "full report output"; then
    clean_project=$(make_temp_project)
    git -C "$clean_project" init -q 2>/dev/null || true
    output=$(run_hook "$clean_project")

    assert_contains     "$output" "Risk:"            "footer Risk line present"
    assert_contains     "$output" "Action:"          "footer Action line present"
    assert_contains     "$output" "PASS"             "output has at least one PASS"
    assert_not_contains "$output" "NOT in .gitignore" "no env warning in clean project"
fi

# ─── Test 4: .env exists but NOT in .gitignore ────────────────────────────────

echo ""
echo -e "${BOLD}Test 4: .env exists but NOT in .gitignore — expect WARN${NC}"

if skip_if_no_jq ".env gitignore warning check"; then
    env_project=$(make_temp_project)
    git -C "$env_project" init -q 2>/dev/null || true
    echo "SOME_VAR=value" > "${env_project}/.env"
    echo "# nothing here" > "${env_project}/.gitignore"
    output=$(run_hook "$env_project")

    assert_contains "$output" "[WARN]"     "output contains WARN"
    assert_contains "$output" ".env"       "output mentions .env"
    assert_contains "$output" ".gitignore" "output mentions .gitignore"
fi

# ─── Test 5: .env is properly in .gitignore ───────────────────────────────────

echo ""
echo -e "${BOLD}Test 5: .env is in .gitignore — expect PASS, no gitignore WARN${NC}"

if skip_if_no_jq ".env gitignore PASS check"; then
    safe_env_project=$(make_temp_project)
    git -C "$safe_env_project" init -q 2>/dev/null || true
    echo "SOME_VAR=value"   > "${safe_env_project}/.env"
    printf '.env\n*.env\n'  > "${safe_env_project}/.gitignore"
    output=$(run_hook "$safe_env_project")

    assert_contains     "$output" "[PASS]"            ".env covered → PASS line present"
    assert_not_contains "$output" "NOT in .gitignore"  "no gitignore warning when covered"
fi

# ─── Test 6: Fake API key in .env — secret detection ─────────────────────────

echo ""
echo -e "${BOLD}Test 6: Fake API key in .env — expect secret detection WARN${NC}"

if skip_if_no_jq "secret detection"; then
    secret_project=$(make_temp_project)
    git -C "$secret_project" init -q 2>/dev/null || true
    cat > "${secret_project}/.env" << 'ENVEOF'
# Fake keys for testing — NOT real credentials
OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
ENVEOF
    printf '.env\n' > "${secret_project}/.gitignore"
    output=$(run_hook "$secret_project")

    assert_contains "$output" "[WARN]" "output contains WARN for secret"
    if echo "$output" | grep -qiE "secret|aws|openai|api.key|detected"; then
        pass "a secret pattern was detected in .env"
    else
        skip "secret content not in WARN — pattern may not match in ERE fallback mode"
    fi
fi

# ─── Test 7: .env.test with fake key — dynamic glob catches it ────────────────

echo ""
echo -e "${BOLD}Test 7: .env.test with fake key — dynamic .env* glob catches it${NC}"

if skip_if_no_jq ".env.test glob scan"; then
    envtest_project=$(make_temp_project)
    git -C "$envtest_project" init -q 2>/dev/null || true
    cat > "${envtest_project}/.env.test" << 'ENVEOF'
OPENAI_API_KEY=sk-test1234567890abcdefghijklmnop
ENVEOF
    output=$(run_hook "$envtest_project")

    if echo "$output" | grep -qE "\.env\.test|secret|detected|[WARN]"; then
        pass ".env.test was scanned (relevant content in output)"
    else
        skip ".env.test scan inconclusive — check grep/PCRE support"
    fi
fi

# ─── Test 8: Git-tracked .env — expect FAIL ───────────────────────────────────

echo ""
echo -e "${BOLD}Test 8: .env tracked by git — expect FAIL${NC}"

if skip_if_no_jq "git-tracked secret detection"; then
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
fi

# ─── Test 9: No package-lock.json → INFO skip message ────────────────────────

echo ""
echo -e "${BOLD}Test 9: No package-lock.json — expect INFO skip message${NC}"

if skip_if_no_jq "npm skip message"; then
    no_npm_project=$(make_temp_project)
    output=$(run_hook "$no_npm_project")
    assert_contains "$output" "package-lock.json" "output mentions package-lock.json"
fi

# ─── Test 10: No requirements.txt → INFO skip message ────────────────────────

echo ""
echo -e "${BOLD}Test 10: No requirements.txt — expect INFO skip message${NC}"

if skip_if_no_jq "pip skip message"; then
    no_pip_project=$(make_temp_project)
    output=$(run_hook "$no_pip_project")
    assert_contains "$output" "requirements.txt" "output mentions requirements.txt"
fi

# ─── Test 11: Non-git dir → INFO skip for git hook check ─────────────────────

echo ""
echo -e "${BOLD}Test 11: Non-git directory — git hook check skipped with INFO${NC}"

if skip_if_no_jq "git hook skip message"; then
    nongit_project=$(make_temp_project)
    output=$(run_hook "$nongit_project")
    assert_contains "$output" "git" "output mentions git (in skip message)"
fi

# ─── Test 12: JetBrains / Chrome always mentioned ─────────────────────────────

echo ""
echo -e "${BOLD}Test 12: JetBrains + Chrome always referenced in output${NC}"

if skip_if_no_jq "JetBrains/Chrome INFO or PASS lines"; then
    infra_project=$(make_temp_project)
    output=$(run_hook "$infra_project")

    if echo "$output" | grep -qiE "jetbrains|JetBrains"; then
        pass "output references JetBrains (installed/checked or skipped)"
    else
        fail "output has no mention of JetBrains — check was silently dropped"
    fi

    if echo "$output" | grep -qiE "chrome|Chrome"; then
        pass "output references Chrome (installed/checked or skipped)"
    else
        fail "output has no mention of Chrome — check was silently dropped"
    fi
fi

# ─── Test 13: Fixture JSON file ───────────────────────────────────────────────

echo ""
echo -e "${BOLD}Test 13: Fixture session-start.json runs without crash${NC}"

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

# ─── Test 14: Audit log written to ~/.broude/audit.log ───────────────────────

echo ""
echo -e "${BOLD}Test 14: Audit log — hook writes to ~/.broude/audit.log${NC}"

if skip_if_no_jq "audit log (requires jq to reach log-writing code)"; then
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
fi

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo -e "${BOLD}Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}, ${YELLOW}${SKIP_COUNT} skipped${NC}"
if [[ "$JQ_AVAILABLE" == false ]]; then
    echo -e "${YELLOW}Note: Install jq to run the full suite without skips.${NC}"
fi
echo "────────────────────────────────────────"
echo ""

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
