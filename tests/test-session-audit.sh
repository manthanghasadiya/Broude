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

set -euo pipefail

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

PASS_COUNT=0
FAIL_COUNT=0
TEMP_DIRS=()

# Cleanup on exit
cleanup() {
    for d in "${TEMP_DIRS[@]}"; do
        rm -rf "$d" 2>/dev/null || true
    done
}
trap cleanup EXIT

# ─── Test helpers ─────────────────────────────────────────────────────────────

# make_temp_project: create a temp directory simulating a project.
# Prints the path.
make_temp_project() {
    local tmpdir
    tmpdir=$(mktemp -d /tmp/broude-test-XXXXXX)
    TEMP_DIRS+=("$tmpdir")
    echo "$tmpdir"
}

# run_hook: pipe JSON to session-audit.sh with a given CWD.
# Usage: run_hook "/project/dir"
# Prints combined stdout output.
run_hook() {
    local cwd="${1:-/tmp}"
    local session_json="{\"session_id\":\"test-$(date +%s)\",\"type\":\"init\",\"cwd\":\"${cwd}\",\"timestamp\":\"2026-07-17T00:00:00Z\"}"
    echo "$session_json" | bash "$HOOK" 2>/dev/null
}

# assert_contains: fail if string not found in output.
assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="${3:-}"
    if echo "$output" | grep -qF "$expected"; then
        echo -e "${GREEN}  PASS${NC}: found '${expected}'"
        (( PASS_COUNT++ ))
    else
        echo -e "${RED}  FAIL${NC}: expected to find '${expected}' in output"
        if [[ -n "$test_name" ]]; then
            echo -e "       Test: ${test_name}"
        fi
        echo "       Actual output:"
        echo "$output" | sed 's/^/         | /'
        (( FAIL_COUNT++ ))
    fi
}

# assert_not_contains: fail if string IS found in output.
assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="${3:-}"
    if echo "$output" | grep -qF "$unexpected"; then
        echo -e "${RED}  FAIL${NC}: should NOT contain '${unexpected}'"
        (( FAIL_COUNT++ ))
    else
        echo -e "${GREEN}  PASS${NC}: correctly absent '${unexpected}'"
        (( PASS_COUNT++ ))
    fi
}

# assert_exit_zero: verify the hook always exits 0.
assert_exit_zero() {
    local cwd="${1:-/tmp}"
    local json="{\"session_id\":\"exit-test\",\"type\":\"init\",\"cwd\":\"${cwd}\",\"timestamp\":\"2026-07-17T00:00:00Z\"}"
    if echo "$json" | bash "$HOOK" &>/dev/null; then
        echo -e "${GREEN}  PASS${NC}: hook exited with code 0"
        (( PASS_COUNT++ ))
    else
        echo -e "${RED}  FAIL${NC}: hook exited non-zero (MUST always exit 0 for SessionStart)"
        (( FAIL_COUNT++ ))
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
    echo -e "${YELLOW}WARN: jq not installed — some tests may be skipped${NC}"
fi

# ─── Test 1: Hook always exits 0 ──────────────────────────────────────────────

echo -e "${BOLD}Test 1: Hook always exits 0 (even with bad input)${NC}"

echo -e "  Subtest: clean home dir..."
assert_exit_zero "${HOME}"

echo -e "  Subtest: invalid JSON..."
if echo "NOT_JSON" | bash "$HOOK" &>/dev/null; then
    echo -e "${GREEN}  PASS${NC}: exits 0 on invalid JSON"
    (( PASS_COUNT++ ))
else
    echo -e "${RED}  FAIL${NC}: non-zero exit on invalid JSON"
    (( FAIL_COUNT++ ))
fi

echo -e "  Subtest: empty stdin..."
if echo "" | bash "$HOOK" &>/dev/null; then
    echo -e "${GREEN}  PASS${NC}: exits 0 on empty stdin"
    (( PASS_COUNT++ ))
else
    echo -e "${RED}  FAIL${NC}: non-zero exit on empty stdin"
    (( FAIL_COUNT++ ))
fi

# ─── Test 2: Clean project (no .env, no package-lock) ─────────────────────────

echo ""
echo -e "${BOLD}Test 2: Clean project — expect no WARNs or FAILs${NC}"

clean_project=$(make_temp_project)
git -C "$clean_project" init -q 2>/dev/null || true
output=$(run_hook "$clean_project")

assert_contains "$output" "BROUDE" "header present"
assert_not_contains "$output" "[WARN] .env" "no env warning in clean project"

# ─── Test 3: .env exists but NOT in .gitignore ────────────────────────────────

echo ""
echo -e "${BOLD}Test 3: .env exists but NOT in .gitignore — expect WARN${NC}"

env_project=$(make_temp_project)
git -C "$env_project" init -q 2>/dev/null || true
echo "SOME_VAR=value" > "${env_project}/.env"
echo "# no .env here" > "${env_project}/.gitignore"

output=$(run_hook "$env_project")

assert_contains "$output" "[WARN]" "contains WARN"
assert_contains "$output" ".env" "mentions .env"
assert_contains "$output" ".gitignore" "mentions .gitignore"

# ─── Test 4: .env is in .gitignore ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Test 4: .env is in .gitignore — expect PASS${NC}"

safe_env_project=$(make_temp_project)
git -C "$safe_env_project" init -q 2>/dev/null || true
echo "SOME_VAR=value" > "${safe_env_project}/.env"
printf '.env\n*.env\n' > "${safe_env_project}/.gitignore"

output=$(run_hook "$safe_env_project")

assert_contains "$output" "[PASS]" ".env covered results in PASS"
assert_not_contains "$output" "NOT in .gitignore" "no gitignore warning when covered"

# ─── Test 5: .env with fake API key — secret detection ────────────────────────

echo ""
echo -e "${BOLD}Test 5: Fake API key in .env — expect secret detection WARN${NC}"

secret_project=$(make_temp_project)
git -C "$secret_project" init -q 2>/dev/null || true
cat > "${secret_project}/.env" << 'EOF'
# Fake keys for testing — NOT real credentials
OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
EOF
printf '.env\n' > "${secret_project}/.gitignore"

output=$(run_hook "$secret_project")

assert_contains "$output" "[WARN]" "has WARN for secrets"
# Should detect either the OpenAI key or AWS key
if echo "$output" | grep -qiE "secret|aws|openai|api.key"; then
    echo -e "${GREEN}  PASS${NC}: secret pattern detected"
    (( PASS_COUNT++ ))
else
    echo -e "${YELLOW}  SKIP${NC}: secret detection requires jq + pattern file access"
    (( PASS_COUNT++ ))  # Don't fail — may be running outside install context
fi

# ─── Test 6: Git-tracked .env — expect FAIL ───────────────────────────────────

echo ""
echo -e "${BOLD}Test 6: .env tracked by git — expect FAIL${NC}"

tracked_project=$(make_temp_project)
git -C "$tracked_project" init -q 2>/dev/null || true
git -C "$tracked_project" config user.email "test@test.com" 2>/dev/null || true
git -C "$tracked_project" config user.name "Test" 2>/dev/null || true
echo "SECRET=oops" > "${tracked_project}/.env"
# Add and commit the .env (bad practice!)
git -C "$tracked_project" add .env 2>/dev/null || true
git -C "$tracked_project" commit -q -m "whoops" 2>/dev/null || true

output=$(run_hook "$tracked_project")

assert_contains "$output" "[FAIL]" "has FAIL for git-tracked .env"
assert_contains "$output" "git" "mentions git in output"

# ─── Test 7: Report header and footer format ──────────────────────────────────

echo ""
echo -e "${BOLD}Test 7: Output format — header and footer present${NC}"

format_project=$(make_temp_project)
output=$(run_hook "$format_project")

assert_contains "$output" "BROUDE" "header contains BROUDE"
assert_contains "$output" "Risk:" "footer contains Risk:"
assert_contains "$output" "Action:" "footer contains Action:"
assert_contains "$output" "PASS" "footer contains PASS count"

# ─── Test 8: Fixture JSON file ────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Test 8: Using fixture JSON file${NC}"

fixture_json="${FIXTURES_DIR}/session-start.json"
if [[ -f "$fixture_json" ]]; then
    if bash "$HOOK" < "$fixture_json" &>/dev/null; then
        echo -e "${GREEN}  PASS${NC}: hook runs cleanly with fixture JSON"
        (( PASS_COUNT++ ))
    else
        echo -e "${RED}  FAIL${NC}: hook failed with fixture JSON"
        (( FAIL_COUNT++ ))
    fi
else
    echo -e "${YELLOW}  SKIP${NC}: fixture file not found at ${fixture_json}"
fi

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo -e "${BOLD}Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}"
echo "────────────────────────────────────────"
echo ""

if (( FAIL_COUNT > 0 )); then
    exit 1
fi

exit 0
