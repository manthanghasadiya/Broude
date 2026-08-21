#!/usr/bin/env bash
# Integration tests for clean install, repeat install, settings merge, and uninstall.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
TEST_ROOT=$(mktemp -d /tmp/broude-install-test-XXXXXX)
INSTALL_DIR="${TEST_ROOT}/broude"
SETTINGS_FILE="${TEST_ROOT}/claude/settings.json"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() { echo "  PASS: $*"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $*"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

assert_jq() {
    local description="$1"
    local expression="$2"
    if jq -e "$expression" "$SETTINGS_FILE" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

run_install() {
    BROUDE_INSTALL_DIR="$INSTALL_DIR" \
    CLAUDE_SETTINGS_FILE="$SETTINGS_FILE" \
    BROUDE_STATE_DIR="$INSTALL_DIR" \
        bash "${REPO_ROOT}/install.sh" >/dev/null
}

run_uninstall() {
    BROUDE_INSTALL_DIR="$INSTALL_DIR" \
    CLAUDE_SETTINGS_FILE="$SETTINGS_FILE" \
        bash "${INSTALL_DIR}/uninstall.sh" >/dev/null
}

echo ""
echo "=== Broude installer lifecycle tests ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    echo "  FAIL: jq is required"
    exit 1
fi

echo "Clean install"
run_install

[[ -x "${INSTALL_DIR}/hooks/session-audit.sh" ]] && pass "session hook installed" || fail "session hook installed"
[[ -x "${INSTALL_DIR}/hooks/pre-bash-check.sh" ]] && pass "command hook installed" || fail "command hook installed"
assert_jq "SessionStart registered" '[.hooks.SessionStart[].hooks[].command | select(endswith("/hooks/session-audit.sh"))] | length == 1'
assert_jq "PreToolUse registered" '[.hooks.PreToolUse[].hooks[].command | select(endswith("/hooks/pre-bash-check.sh"))] | length == 1'

echo ""
echo "Repeat install"
run_install
assert_jq "SessionStart remains unique" '[.hooks.SessionStart[].hooks[].command | select(endswith("/hooks/session-audit.sh"))] | length == 1'
assert_jq "PreToolUse remains unique" '[.hooks.PreToolUse[].hooks[].command | select(endswith("/hooks/pre-bash-check.sh"))] | length == 1'

echo ""
echo "Merge with unrelated settings"
jq '.theme = "dark" | .hooks.SessionStart += [{"hooks":[{"type":"command","command":"/opt/example/session.sh"}]}] | .hooks.PreToolUse += [{"matcher":"Write","hooks":[{"type":"command","command":"/opt/example/write.sh"}]}]' \
    "$SETTINGS_FILE" > "${TEST_ROOT}/settings-with-custom.json"
cp "${TEST_ROOT}/settings-with-custom.json" "$SETTINGS_FILE"
run_install
assert_jq "unrelated setting preserved" '.theme == "dark"'
assert_jq "unrelated SessionStart hook preserved" '[.hooks.SessionStart[].hooks[].command | select(. == "/opt/example/session.sh")] | length == 1'
assert_jq "unrelated PreToolUse hook preserved" '[.hooks.PreToolUse[].hooks[].command | select(. == "/opt/example/write.sh")] | length == 1'

echo ""
echo "Uninstall"
run_uninstall
[[ ! -d "$INSTALL_DIR" ]] && pass "installation directory removed" || fail "installation directory removed"
assert_jq "Broude SessionStart removed" '[.hooks.SessionStart[]?.hooks[]?.command | select(contains("broude"))] | length == 0'
assert_jq "Broude PreToolUse removed" '[.hooks.PreToolUse[]?.hooks[]?.command | select(contains("broude"))] | length == 0'
assert_jq "unrelated hooks survive uninstall" '([.hooks.SessionStart[].hooks[].command | select(. == "/opt/example/session.sh")] | length == 1) and ([.hooks.PreToolUse[].hooks[].command | select(. == "/opt/example/write.sh")] | length == 1)'

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, $(( PASS_COUNT + FAIL_COUNT )) total"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
