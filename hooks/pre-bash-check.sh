#!/usr/bin/env bash
# broude/hooks/pre-bash-check.sh - PreToolUse blocking hook
#
# Triggered by Claude Code BEFORE every Bash tool execution.
# Reads PreToolUse JSON from stdin, checks the command for:
#   1. GuardFall obfuscation patterns (5 classes from Adversa AI research)
#   2. Pipe-to-shell patterns (curl/wget | bash/sh/python/node)
#   3. Catastrophically dangerous commands (rm -rf /, mkfs, dd to /dev/sda, etc.)
#
# EXIT CODES:
#   0 = allow the command to proceed
#   2 = BLOCK the command (stderr sent to Claude, JSON on stdout)
#
# CRITICAL: This runs on EVERY bash command Claude tries to run.
# It MUST be fast (< 500ms) and MUST exit 0 on any internal error (fail open).
# Never block a command due to a broude bug.
#
# DO NOT use set -euo pipefail — learned from Phase 1.

# ─── Crash handler: always fail open ─────────────────────────────────────────
_broude_pre_crashed() {
    echo "[BROUDE WARN] pre-bash-check crashed unexpectedly (line ${1}) — allowing command." >&2
    exit 0
}
trap '_broude_pre_crashed ${LINENO}' ERR

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"
GUARDFALL_PATTERNS="${DATA_DIR}/guardfall-patterns.json"

# ─── Source shared libraries ─────────────────────────────────────────────────
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/guardfall-checker.sh
source "${SCRIPT_DIR}/lib/guardfall-checker.sh"
# shellcheck source=lib/pipe-checker.sh
source "${SCRIPT_DIR}/lib/pipe-checker.sh"

# ─── Helpers ─────────────────────────────────────────────────────────────────

# _truncate: truncate a string to N chars for display in block messages
_truncate() {
    local str="$1"
    local max="${2:-120}"
    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$max}..."
    else
        echo "$str"
    fi
}

# _block: emit block message + JSON and exit 2
# Usage: _block "REASON TEXT" "full_command"
_block() {
    local reason="$1"
    local full_cmd="$2"
    local truncated
    truncated="$(_truncate "$full_cmd" 120)"

    # Log to audit file
    audit_log "BLOCK" "${reason} | cmd: ${full_cmd}"

    # Stderr message goes to Claude (exit code 2 routes stderr to the model)
    echo "[BROUDE BLOCK] ${reason} | Command: ${truncated}" >&2

    # Optional structured JSON on stdout for Claude Code hook framework
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","additionalContext":"BROUDE BLOCKED: %s"}}\n' \
        "$reason"

    exit 2
}

# ─── Bootstrap: read and parse stdin ─────────────────────────────────────────

# Slurp all stdin before anything else
_RAW_STDIN="$(cat)"

_JQ_OK=false
if command -v jq &>/dev/null; then
    _JQ_OK=true
fi

# Extract fields — try jq first, fall back to grep for basic extraction
_TOOL_NAME=""
_COMMAND=""
_SESSION_ID=""

if [[ "$_JQ_OK" == "true" ]]; then
    # Validate JSON first
    if ! echo "$_RAW_STDIN" | jq empty 2>/dev/null; then
        audit_log "WARN" "pre-bash-check: invalid JSON on stdin, skipping checks"
        exit 0
    fi
    _TOOL_NAME=$(echo "$_RAW_STDIN" | jq -r '.tool_name // empty' 2>/dev/null)
    _COMMAND=$(echo "$_RAW_STDIN" | jq -r '.tool_input.command // empty' 2>/dev/null)
    _SESSION_ID=$(echo "$_RAW_STDIN" | jq -r '.session_id // empty' 2>/dev/null)
else
    # grep-based fallback — handles simple (non-nested-quote) commands
    # Sufficient for extracting the command from a well-formed PreToolUse payload
    _TOOL_NAME=$(echo "$_RAW_STDIN" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' 2>/dev/null || true)
    _COMMAND=$(echo "$_RAW_STDIN" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' 2>/dev/null || true)
    _SESSION_ID=$(echo "$_RAW_STDIN" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' 2>/dev/null || true)
    # Note: grep fallback will miss commands with escaped quotes — those pass through safely
fi

# Only act on Bash tool calls — pass through everything else silently
if [[ "$_TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

# Empty or whitespace-only command — nothing to check
_CMD_TRIMMED="${_COMMAND#"${_COMMAND%%[![:space:]]*}"}"
_CMD_TRIMMED="${_CMD_TRIMMED%"${_CMD_TRIMMED##*[![:space:]]}"}"
if [[ -z "$_CMD_TRIMMED" ]]; then
    exit 0
fi

# Comment-only command — skip
if [[ "$_CMD_TRIMMED" == \#* ]]; then
    exit 0
fi

# Allowlist check — if command is trusted (e.g. Broude installation), skip all checks
if _is_allowlisted "$_COMMAND"; then
    audit_log "ALLOW" "pre-bash-check: command is allowlisted | session=${_SESSION_ID} | cmd=$(_truncate "$_COMMAND" 200)"
    exit 0
fi

# ─── Load GuardFall patterns (cached in memory for this process) ──────────────
load_guardfall_patterns "$GUARDFALL_PATTERNS"
# If patterns fail to load, GuardFall check will be a no-op (fail open)

# ─── Check 1: GuardFall Obfuscation ──────────────────────────────────────────
_gf_result=$(check_guardfall "$_COMMAND")

if [[ -n "$_gf_result" ]]; then
    # Parse: class_id|class_name|pat_id|pat_name|severity
    _gf_class_id=$(echo "$_gf_result" | cut -d'|' -f1)
    _gf_class_name=$(echo "$_gf_result" | cut -d'|' -f2)
    _gf_pat_name=$(echo "$_gf_result" | cut -d'|' -f4)
    _gf_severity=$(echo "$_gf_result" | cut -d'|' -f5)

    # Map class-a → Class A, class-b → Class B, etc.
    _gf_class_letter=$(echo "$_gf_class_id" | sed 's/class-//' | tr '[:lower:]' '[:upper:]')

    _block \
        "Obfuscated command detected (GuardFall Class ${_gf_class_letter}: ${_gf_pat_name}) [${_gf_severity}]" \
        "$_COMMAND"
fi

# ─── Check 2: Pipe-to-Shell ───────────────────────────────────────────────────
_pipe_result=$(check_pipe_to_shell "$_COMMAND")

if [[ -n "$_pipe_result" ]]; then
    _block \
        "Pipe-to-shell detected: ${_pipe_result} is blocked" \
        "$_COMMAND"
fi

# ─── Check 3: Dangerous Commands ─────────────────────────────────────────────
_danger_result=$(check_dangerous_command "$_COMMAND")

if [[ -n "$_danger_result" ]]; then
    _block \
        "Dangerous command blocked: ${_danger_result}" \
        "$_COMMAND"
fi

# ─── All checks passed — allow ────────────────────────────────────────────────
audit_log "ALLOW" "pre-bash-check: command passed all checks | session=${_SESSION_ID} | cmd=$(_truncate "$_COMMAND" 200)"
exit 0
