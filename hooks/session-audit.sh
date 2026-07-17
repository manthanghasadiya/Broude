#!/usr/bin/env bash
# broude/hooks/session-audit.sh - SessionStart security audit hook
#
# Triggered by Claude Code on SessionStart events.
# Reads JSON from stdin, runs security checks, outputs a report to stdout.
# Claude will inject this output into its context.
#
# EXIT CODE: Always 0. Session audit is informational — never blocks session start.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"

# Source shared libraries
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/secret-scanner.sh
source "${SCRIPT_DIR}/lib/secret-scanner.sh"
# shellcheck source=lib/dep-checker.sh
source "${SCRIPT_DIR}/lib/dep-checker.sh"

# ─── Bootstrap ────────────────────────────────────────────────────────────────

# Verify jq is present — fail gracefully, never block
check_deps || exit 0

# Read and validate stdin JSON
read_stdin_json || exit 0

# Extract working directory from session event
CWD=$(get_json_field ".cwd")
if [[ -z "$CWD" ]]; then
    CWD="$(pwd)"
fi

SESSION_ID=$(get_json_field ".session_id")

# Print report header
print_header "Session Security Audit" "$CWD"

# Log session start
audit_log "INFO" "Session audit started | session=${SESSION_ID} | cwd=${CWD}"

# ─── 1. Secret exposure check ─────────────────────────────────────────────────

# List of common files that frequently contain secrets
SECRET_FILES=(
    ".env"
    ".env.local"
    ".env.development"
    ".env.staging"
    ".env.production"
    ".env.test"
    "config.json"
    "config.yaml"
    "config.yml"
    "settings.py"
    "local_settings.py"
    "application.yml"
    "application.yaml"
    "application.properties"
    ".netrc"
    "secrets.json"
    "credentials.json"
    ".aws/credentials"
    ".npmrc"
)

# Load secret patterns from data file
PATTERNS_FILE="${DATA_DIR}/secret-patterns.json"
_patterns_loaded=false
if [[ -f "$PATTERNS_FILE" ]]; then
    if load_secret_patterns "$PATTERNS_FILE"; then
        _patterns_loaded=true
    fi
fi

_secret_issues=0

if [[ "$_patterns_loaded" == "true" ]]; then
    _scanned_files=0
    _files_with_secrets=()

    for rel_file in "${SECRET_FILES[@]}"; do
        abs_file="${CWD}/${rel_file}"
        if [[ -f "$abs_file" ]]; then
            (( _scanned_files++ ))
            matches=$(scan_file_for_secrets "$abs_file")
            if [[ -n "$matches" ]]; then
                _files_with_secrets+=("$rel_file")
                # Print each match (dedup by pattern name)
                while IFS= read -r match_line; do
                    local_line=$(echo "$match_line" | cut -d: -f2)
                    severity=$(echo "$match_line" | cut -d: -f3)
                    pattern_name=$(echo "$match_line" | cut -d: -f4-)
                    log_warn "Secret detected in ${rel_file}:${local_line} — ${pattern_name} [${severity}]"
                    audit_log "WARN" "Secret in ${rel_file}:${local_line} | ${pattern_name} | ${severity}"
                    (( _secret_issues++ ))
                done <<< "$matches"
            fi
        fi
    done

    if (( _secret_issues == 0 )); then
        log_pass "No secrets detected in project files"
    fi
else
    log_info "Secret pattern file not found — secret scan skipped"
fi

# Check .gitignore coverage for .env files
_env_status=$(check_env_in_gitignore "$CWD")
case "$_env_status" in
    "covered")
        if [[ -f "${CWD}/.env" ]]; then
            log_pass ".env is in .gitignore"
        fi
        ;;
    "missing")
        if [[ -f "${CWD}/.env" ]]; then
            log_warn ".env file exists but is NOT in .gitignore — add '.env' to .gitignore"
            audit_log "WARN" ".env not in .gitignore | cwd=${CWD}"
        fi
        ;;
    "no_gitignore")
        if [[ -f "${CWD}/.env" ]]; then
            log_warn ".env file exists and no .gitignore found — create .gitignore and add '.env'"
            audit_log "WARN" "No .gitignore found | cwd=${CWD}"
        fi
        ;;
esac

# Check for .env files already tracked by git
_tracked=$(check_git_tracked_secrets "$CWD")
if [[ -n "$_tracked" ]]; then
    while IFS= read -r tracked_file; do
        log_fail "Secret file already tracked by git: ${tracked_file}"
        log_fail "  → Run: git rm --cached '${tracked_file}' && git commit -m 'remove tracked secrets'"
        audit_log "FAIL" "Git-tracked secret file: ${tracked_file}"
    done <<< "$_tracked"
fi

# ─── 2. npm dependency audit ──────────────────────────────────────────────────

check_npm_deps "$CWD"

# ─── 3. pip dependency audit ──────────────────────────────────────────────────

check_pip_deps "$CWD"

# ─── 4. JetBrains plugin check ────────────────────────────────────────────────

PLUGINS_FILE="${DATA_DIR}/malicious-plugins.json"
check_jetbrains_plugins "$PLUGINS_FILE"

# ─── 5. Chrome extension check ───────────────────────────────────────────────

EXTENSIONS_FILE="${DATA_DIR}/malicious-extensions.json"
check_chrome_extensions "$EXTENSIONS_FILE"

# ─── 6. Git hook security check ───────────────────────────────────────────────

_git_hooks_dir="${CWD}/.git/hooks"
if [[ -d "$_git_hooks_dir" ]]; then
    _suspicious_hooks=()

    # Scan all hook scripts for curl/wget that download external scripts
    while IFS= read -r -d '' hook_file; do
        hook_name="$(basename "$hook_file")"
        # Skip sample files
        [[ "$hook_name" == *.sample ]] && continue
        # Skip non-executable or non-text files
        [[ ! -x "$hook_file" ]] && continue

        # Look for external download patterns: curl | bash, wget | sh, etc.
        if grep -qE '(curl|wget)[[:space:]].*\|[[:space:]]*(bash|sh|zsh|python|node)' "$hook_file" 2>/dev/null; then
            _suspicious_hooks+=("${hook_name}: downloads and executes external script")
        elif grep -qE '(curl|wget)[[:space:]].*(-O|-o|--output|>)[[:space:]]*[^/]' "$hook_file" 2>/dev/null; then
            _suspicious_hooks+=("${hook_name}: downloads external file")
        fi
    done < <(find "$_git_hooks_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    if (( ${#_suspicious_hooks[@]} == 0 )); then
        log_pass "Git hooks look clean"
    else
        for suspicious in "${_suspicious_hooks[@]}"; do
            log_warn "Suspicious git hook — ${suspicious}"
            audit_log "WARN" "Suspicious git hook: ${suspicious}"
        done
    fi
fi

# ─── Footer ───────────────────────────────────────────────────────────────────

print_footer
audit_log "INFO" "Session audit complete | pass=${_PASS_COUNT} warn=${_WARN_COUNT} fail=${_FAIL_COUNT}"

# ALWAYS exit 0 — never block a session from starting
exit 0
