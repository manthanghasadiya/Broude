#!/usr/bin/env bash
# broude/hooks/session-audit.sh - SessionStart security audit hook
#
# Triggered by Claude Code on SessionStart events.
# Reads JSON from stdin, runs security checks, outputs a report to stdout.
# Claude will inject this output into its context.
#
# EXIT CODE: Always 0. Session audit is informational — never blocks session start.

# Bug 1 fix: no set -euo pipefail — it causes any subcommand failure to propagate.
# Instead we handle errors explicitly and use a global trap to guarantee exit 0.
_broude_crashed() {
    echo ""
    echo "[BROUDE ERROR] Audit crashed unexpectedly (line ${1}). Session is unaffected."
    echo ""
    exit 0
}
trap '_broude_crashed ${LINENO}' ERR

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

# Slurp stdin first (before anything that might consume it)
_RAW_STDIN="$(cat)"

# Determine CWD:
#   1. Use jq to parse the session JSON if available
#   2. Fall back to a grep extraction from raw stdin
#   3. Default to pwd
CWD=""
SESSION_ID=""
_JQ_OK=false

if command -v jq &>/dev/null; then
    _JQ_OK=true
    if echo "$_RAW_STDIN" | jq empty 2>/dev/null; then
        _STDIN_JSON="$_RAW_STDIN"
        CWD=$(echo "$_STDIN_JSON" | jq -r '.cwd // empty' 2>/dev/null)
        SESSION_ID=$(echo "$_STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null)
    fi
fi

# Fallback: extract cwd from raw JSON via grep (no jq needed)
if [[ -z "$CWD" ]]; then
    CWD=$(echo "$_RAW_STDIN" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | grep -o '"[^"]*"$' | tr -d '"' 2>/dev/null || true)
fi

# Final fallback: current working directory
if [[ -z "$CWD" ]] || [[ ! -d "$CWD" ]]; then
    CWD="$(pwd)"
fi

# Print report header — always runs, even if jq is missing
print_header "Session Security Audit" "$CWD"

# Warn about missing jq but DO NOT exit — most checks are pure bash
if [[ "$_JQ_OK" == false ]]; then
    log_warn "jq is not installed — secret pattern scan and dep audit unavailable"
    log_warn "  Install jq: macOS: brew install jq | Ubuntu: sudo apt-get install -y jq"
fi

# Log session start (best-effort — audit_log is a no-op if dir unwritable)
audit_log "INFO" "Session audit started | session=${SESSION_ID} | cwd=${CWD}"

# ─── 1. Secret exposure check ─────────────────────────────────────────────────

# List of common files that frequently contain secrets.
# Also glob any .env* files present in CWD at scan time.
SECRET_FILES_STATIC=(
    ".env"
    ".env.local"
    ".env.development"
    ".env.staging"
    ".env.production"
    ".env.test"
    ".env.example"
    ".env.sample"
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

# Dynamically add any .env* files found in CWD that aren't already in the list
SECRET_FILES=("${SECRET_FILES_STATIC[@]}")
while IFS= read -r -d '' found_env; do
    rel="${found_env#${CWD}/}"
    # Only add if not already in the static list
    already=false
    for existing in "${SECRET_FILES_STATIC[@]}"; do
        [[ "$existing" == "$rel" ]] && { already=true; break; }
    done
    [[ "$already" == false ]] && SECRET_FILES+=("$rel")
done < <(find "$CWD" -maxdepth 1 -name '.env*' -type f -print0 2>/dev/null)

# Load secret patterns from data file (requires jq)
PATTERNS_FILE="${DATA_DIR}/secret-patterns.json"
_patterns_loaded=false
if [[ "$_JQ_OK" == true ]] && [[ -f "$PATTERNS_FILE" ]]; then
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
            _scanned_files=$(( _scanned_files + 1 ))
            matches=$(scan_file_for_secrets "$abs_file") || true
            if [[ -n "$matches" ]]; then
                _files_with_secrets+=("$rel_file")
                while IFS= read -r match_line; do
                    local_line=$(echo "$match_line" | cut -d: -f2)
                    severity=$(echo "$match_line" | cut -d: -f3)
                    pattern_name=$(echo "$match_line" | cut -d: -f4-)
                    log_warn "Secret detected in ${rel_file}:${local_line} — ${pattern_name} [${severity}]"
                    audit_log "WARN" "Secret in ${rel_file}:${local_line} | ${pattern_name} | ${severity}"
                    _secret_issues=$(( _secret_issues + 1 ))
                done <<< "$matches"
            fi
        fi
    done

    if (( _secret_issues == 0 )); then
        if (( _scanned_files > 0 )); then
            log_pass "No secrets detected in project files (${_scanned_files} files scanned)"
        else
            log_pass "No sensitive config files found in project root"
        fi
    fi
else
    if [[ "$_JQ_OK" == false ]]; then
        log_info "Secret pattern scan skipped (jq required)"
    else
        log_info "Secret pattern file not found — secret scan skipped"
    fi
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

if [[ "$_JQ_OK" == false ]]; then
    log_info "npm audit skipped (jq required to parse results)"
elif [[ ! -f "${CWD}/package-lock.json" ]]; then
    log_info "npm: no package-lock.json found — skipping npm audit"
else
    check_npm_deps "$CWD"
fi

# ─── 3. pip dependency audit ──────────────────────────────────────────────────

if [[ "$_JQ_OK" == false ]]; then
    log_info "pip-audit skipped (jq required to parse results)"
elif [[ ! -f "${CWD}/requirements.txt" ]]; then
    log_info "pip: no requirements.txt found — skipping pip-audit"
else
    check_pip_deps "$CWD"
fi

# ─── 4. JetBrains plugin check ─────────────────────────────────────────────────

PLUGINS_FILE="${DATA_DIR}/malicious-plugins.json"
if [[ "$_JQ_OK" == false ]]; then
    log_info "JetBrains plugin check skipped (jq required)"
else
    check_jetbrains_plugins "$PLUGINS_FILE"
fi

# ─── 5. Chrome extension check ───────────────────────────────────────────────

EXTENSIONS_FILE="${DATA_DIR}/malicious-extensions.json"
if [[ "$_JQ_OK" == false ]]; then
    log_info "Chrome extension check skipped (jq required)"
else
    check_chrome_extensions "$EXTENSIONS_FILE"
fi

if (( _PASS_COUNT + _WARN_COUNT + _FAIL_COUNT == 0 )); then
    # Safety net: if somehow nothing was logged, emit a neutral status
    log_info "No checks produced output — environment may be minimal"
fi

# ─── 6. Git hook security check ───────────────────────────────────────────────

_git_hooks_dir="${CWD}/.git/hooks"
if [[ ! -d "${CWD}/.git" ]]; then
    log_info "git: not a git repository — skipping git hook check"
elif [[ ! -d "$_git_hooks_dir" ]]; then
    log_info "git: no .git/hooks directory — skipping git hook check"
else
    _suspicious_hooks=()

    # Scan all hook scripts for curl/wget that download external scripts
    while IFS= read -r -d '' hook_file; do
        hook_name="$(basename "$hook_file")"
        # Skip sample files
        [[ "$hook_name" == *.sample ]] && continue
        # Skip non-executable files
        [[ ! -x "$hook_file" ]] && continue

        # Look for external download patterns: curl | bash, wget | sh, etc.
        if grep -qE '(curl|wget)[[:space:]].*\|[[:space:]]*(bash|sh|zsh|python|node)' "$hook_file" 2>/dev/null; then
            _suspicious_hooks+=("${hook_name}: downloads and executes external script")
        elif grep -qE '(curl|wget)[[:space:]].*(-O|-o|--output|>)[[:space:]]*[^/]' "$hook_file" 2>/dev/null; then
            _suspicious_hooks+=("${hook_name}: downloads external file")
        fi
    done < <(find "$_git_hooks_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    if (( ${#_suspicious_hooks[@]} == 0 )); then
        log_pass "Git hooks look clean (no external download patterns)"
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
