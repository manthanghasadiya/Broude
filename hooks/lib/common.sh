#!/usr/bin/env bash
# broude/hooks/lib/common.sh - shared utilities for all Broude hooks
# Source this at the top of every hook script.

BROUDE_VERSION="1.1.1"
BROUDE_DIR="${HOME}/.broude"
BROUDE_LOG="${BROUDE_DIR}/audit.log"

# Internal counters (reset per hook run)
_PASS_COUNT=0
_WARN_COUNT=0
_FAIL_COUNT=0

# Colors (only if stdout is a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ─── Dependency check ────────────────────────────────────────────────────────

# check_deps: verify jq is installed. Exits with message if missing.
# Returns 0 if OK, 1 if jq missing.
check_deps() {
    if ! command -v jq &>/dev/null; then
        echo "[BROUDE ERROR] jq is required but not installed."
        echo "  Install it with:"
        echo "    macOS:  brew install jq"
        echo "    Ubuntu: sudo apt-get install -y jq"
        echo "    Fedora: sudo dnf install -y jq"
        echo "  Then restart your Claude Code session."
        return 1
    fi
    return 0
}

# ─── JSON helpers ─────────────────────────────────────────────────────────────

# Stores the raw stdin JSON after read_stdin_json succeeds
_STDIN_JSON=""

# read_stdin_json: read all stdin into _STDIN_JSON and validate it's valid JSON.
# Returns 0 on success, 1 on failure.
read_stdin_json() {
    _STDIN_JSON="$(cat)"
    if [[ -z "$_STDIN_JSON" ]]; then
        echo "[BROUDE WARN] No JSON received on stdin — skipping checks." >&2
        return 1
    fi
    if ! echo "$_STDIN_JSON" | jq empty 2>/dev/null; then
        echo "[BROUDE WARN] Received invalid JSON on stdin — skipping checks." >&2
        return 1
    fi
    return 0
}

# get_json_field: extract a jq path from _STDIN_JSON.
# Usage: get_json_field ".some.field"
# Prints the raw (unquoted) string value or empty string if missing/null.
get_json_field() {
    local path="$1"
    echo "$_STDIN_JSON" | jq -r "$path // empty" 2>/dev/null
}

# ─── Logging / output formatting ─────────────────────────────────────────────

log_pass() {
    local msg="$*"
    echo -e "${GREEN}[PASS]${NC} ${msg}"
    _PASS_COUNT=$(( _PASS_COUNT + 1 ))
}

log_warn() {
    local msg="$*"
    echo -e "${YELLOW}[WARN]${NC} ${msg}"
    _WARN_COUNT=$(( _WARN_COUNT + 1 ))
}

log_fail() {
    local msg="$*"
    echo -e "${RED}[FAIL]${NC} ${msg}"
    _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
}

log_info() {
    local msg="$*"
    echo -e "${CYAN}[INFO]${NC} ${msg}"
}

# print_header: print the Broude session audit report header.
# Usage: print_header "Title" "/optional/project/path"
print_header() {
    local title="${1:-Session Security Audit}"
    local project="${2:-}"
    echo ""
    echo -e "${BOLD}=== BROUDE v${BROUDE_VERSION}: ${title} ===${NC}"
    if [[ -n "$project" ]]; then
        echo ""
        echo "Project: ${project}"
    fi
    echo ""
}

# print_footer: print summary line with risk level based on counts.
print_footer() {

    # Determine risk level
    local risk
    if (( _FAIL_COUNT > 0 )); then
        risk="HIGH"
    elif (( _WARN_COUNT > 0 )); then
        risk="MEDIUM"
    else
        risk="LOW"
    fi

    echo ""

    # Build action advice
    local actions=()
    if (( _FAIL_COUNT > 0 )); then
        actions+=("Review FAIL items immediately.")
    fi
    if (( _WARN_COUNT > 0 )); then
        actions+=("Address WARN items before committing.")
    fi
    if (( ${#actions[@]} == 0 )); then
        actions+=("No action required.")
    fi

    echo -e "Risk: ${BOLD}${risk}${NC} (${_PASS_COUNT} PASS, ${_WARN_COUNT} WARN, ${_FAIL_COUNT} FAIL)"
    echo "Action: ${actions[*]}"
    echo "=========================================="
    echo ""
}

# ─── Audit log ────────────────────────────────────────────────────────────────

# audit_log: append a timestamped entry to ~/.broude/audit.log.
# Usage: audit_log "level" "message"
audit_log() {
    local level="${1:-INFO}"
    local msg="${2:-}"
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"

    # Create dir if needed
    if [[ ! -d "$BROUDE_DIR" ]]; then
        mkdir -p "$BROUDE_DIR" 2>/dev/null || return 0
    fi

    printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" >> "$BROUDE_LOG" 2>/dev/null || true
}
