#!/usr/bin/env bash
# broude/hooks/lib/dep-checker.sh - dependency validation
# Source this file (do not execute directly).
# Requires: common.sh sourced first, jq available.
# Design principle: delegate heavy lifting to existing tools (npm audit, pip-audit).
# Broude does NOT maintain its own package vulnerability database.

# ─── npm audit ────────────────────────────────────────────────────────────────

# check_npm_deps: run npm audit if package-lock.json is present and npm available.
# Usage: check_npm_deps "/project/dir"
# Calls log_pass/log_warn/log_fail/log_info from common.sh
check_npm_deps() {
    local project_dir="${1:-.}"

    if [[ ! -f "${project_dir}/package-lock.json" ]]; then
        return 0  # Not a Node project (or no lock file), skip silently
    fi

    if ! command -v npm &>/dev/null; then
        log_info "npm not found — skipping npm vulnerability audit"
        return 0
    fi

    log_info "Running npm audit..."

    local audit_output
    audit_output=$(cd "$project_dir" && npm audit --json 2>/dev/null)

    if [[ -z "$audit_output" ]]; then
        log_warn "npm audit: no output received (try running 'npm install' first)"
        return 0
    fi

    # npm audit --json top-level has a "metadata" key when there are results
    local total critical high moderate low info
    total=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.total // 0' 2>/dev/null)
    critical=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.critical // 0' 2>/dev/null)
    high=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.high // 0' 2>/dev/null)
    moderate=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.moderate // 0' 2>/dev/null)
    low=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.low // 0' 2>/dev/null)
    info=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.info // 0' 2>/dev/null)

    # Numeric defaults in case jq returns "null"
    total=${total:-0}; critical=${critical:-0}; high=${high:-0}
    moderate=${moderate:-0}; low=${low:-0}; info=${info:-0}

    if (( total == 0 )); then
        log_pass "npm audit: 0 vulnerabilities"
    elif (( critical > 0 || high > 0 )); then
        log_fail "npm audit: ${total} vulnerabilities (${critical} critical, ${high} high, ${moderate} moderate, ${low} low)"
    elif (( moderate > 0 )); then
        log_warn "npm audit: ${total} vulnerabilities (0 critical, 0 high, ${moderate} moderate, ${low} low)"
    else
        log_warn "npm audit: ${total} vulnerabilities (${low} low, ${info} info)"
    fi

    return 0
}

# ─── pip-audit ────────────────────────────────────────────────────────────────

# check_pip_deps: run pip-audit if requirements.txt is present and pip-audit available.
# Usage: check_pip_deps "/project/dir"
check_pip_deps() {
    local project_dir="${1:-.}"

    if [[ ! -f "${project_dir}/requirements.txt" ]]; then
        return 0  # Not a Python project (or no requirements file), skip silently
    fi

    if ! command -v pip-audit &>/dev/null; then
        log_info "pip-audit not found — skipping Python vulnerability audit"
        log_info "  Install with: pip install pip-audit"
        return 0
    fi

    log_info "Running pip-audit..."

    local audit_output
    audit_output=$(pip-audit --requirement "${project_dir}/requirements.txt" --format=json 2>/dev/null)

    if [[ -z "$audit_output" ]]; then
        log_warn "pip-audit: no output received"
        return 0
    fi

    # pip-audit JSON: array of objects with "vulns" arrays
    local total_vulns
    total_vulns=$(echo "$audit_output" | jq '[.[].vulns[]] | length' 2>/dev/null)
    total_vulns=${total_vulns:-0}

    if (( total_vulns == 0 )); then
        log_pass "pip-audit: 0 vulnerabilities"
    else
        # Count by severity if available (newer pip-audit versions include fix_versions)
        local critical high moderate
        critical=$(echo "$audit_output" | jq '[.[].vulns[] | select(.fix_versions == null or .fix_versions == [])] | length' 2>/dev/null || echo 0)
        log_fail "pip-audit: ${total_vulns} vulnerabilities found in Python dependencies"
    fi

    return 0
}

# ─── JetBrains plugin check ───────────────────────────────────────────────────

# _get_jetbrains_dirs: print all JetBrains plugin directories that exist on this system.
_get_jetbrains_dirs() {
    local dirs=()

    # Linux paths
    if [[ -d "${HOME}/.config/JetBrains" ]]; then
        while IFS= read -r -d '' dir; do
            local plugins_dir="${dir}/plugins"
            [[ -d "$plugins_dir" ]] && dirs+=("$plugins_dir")
        done < <(find "${HOME}/.config/JetBrains" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    # macOS paths
    if [[ -d "${HOME}/Library/Application Support/JetBrains" ]]; then
        while IFS= read -r -d '' dir; do
            local plugins_dir="${dir}/plugins"
            [[ -d "$plugins_dir" ]] && dirs+=("$plugins_dir")
        done < <(find "${HOME}/Library/Application Support/JetBrains" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    printf '%s\n' "${dirs[@]}"
}

# check_jetbrains_plugins: scan JetBrains plugin dirs against malicious-plugins.json.
# Usage: check_jetbrains_plugins "/path/to/data/malicious-plugins.json"
check_jetbrains_plugins() {
    local data_file="${1:-}"
    if [[ -z "$data_file" ]] || [[ ! -f "$data_file" ]]; then
        return 0
    fi

    # Collect JetBrains plugin dirs
    local plugin_dirs
    mapfile -t plugin_dirs < <(_get_jetbrains_dirs)

    if (( ${#plugin_dirs[@]} == 0 )); then
        log_info "JetBrains: not installed — skipping plugin check"
        return 0
    fi

    # Load malicious plugin IDs and names from JSON
    local mal_count
    mal_count=$(jq '.plugins | length' "$data_file" 2>/dev/null)
    if [[ -z "$mal_count" ]] || (( mal_count == 0 )); then
        return 0
    fi

    local found_any=0
    local found_malicious=0

    for plugins_dir in "${plugin_dirs[@]}"; do
        # Each plugin in JetBrains has a descriptor: plugin.xml or META-INF/plugin.xml
        while IFS= read -r -d '' xml_file; do
            # Extract plugin ID from XML
            local plugin_id
            plugin_id=$(grep -oP '(?<=<id>)[^<]+(?=</id>)' "$xml_file" 2>/dev/null | head -1)
            if [[ -z "$plugin_id" ]]; then
                continue
            fi

            # Cross-reference against malicious plugins list
            local match_name
            match_name=$(jq -r --arg id "$plugin_id" \
                '.plugins[] | select(.id == $id) | .name' "$data_file" 2>/dev/null | head -1)

            if [[ -n "$match_name" ]]; then
                log_fail "Malicious JetBrains plugin detected: \"${match_name}\" (ID: ${plugin_id})"
                log_fail "  → Uninstall immediately via Settings → Plugins → Uninstall"
                audit_log "FAIL" "Malicious JetBrains plugin: ${plugin_id} (${match_name})"
                found_malicious=$(( found_malicious + 1 ))
            fi
            found_any=$(( found_any + 1 ))
        done < <(find "$plugins_dir" -name "plugin.xml" -print0 2>/dev/null)
    done

    if (( found_malicious == 0 )); then
        if (( found_any > 0 )); then
            log_pass "No malicious JetBrains plugins detected (${found_any} plugins checked)"
        else
            log_pass "No malicious JetBrains plugins detected"
        fi
    fi

    return 0
}

# ─── Chrome extension check ───────────────────────────────────────────────────

# _get_chrome_extension_dirs: print Chrome extension base directories that exist.
_get_chrome_extension_dirs() {
    local candidates=(
        "${HOME}/.config/google-chrome/Default/Extensions"
        "${HOME}/.config/chromium/Default/Extensions"
        "${HOME}/Library/Application Support/Google/Chrome/Default/Extensions"
        "${HOME}/Library/Application Support/Chromium/Default/Extensions"
        "${HOME}/snap/chromium/current/.config/chromium/Default/Extensions"
    )
    for d in "${candidates[@]}"; do
        [[ -d "$d" ]] && echo "$d"
    done
}

# check_chrome_extensions: scan Chrome extensions against malicious-extensions.json.
# Usage: check_chrome_extensions "/path/to/data/malicious-extensions.json"
check_chrome_extensions() {
    local data_file="${1:-}"
    if [[ -z "$data_file" ]] || [[ ! -f "$data_file" ]]; then
        return 0
    fi

    local ext_base_dirs
    mapfile -t ext_base_dirs < <(_get_chrome_extension_dirs)

    if (( ${#ext_base_dirs[@]} == 0 )); then
        log_info "Chrome: not installed — skipping extension check"
        return 0
    fi

    local mal_count
    mal_count=$(jq '.extensions | length' "$data_file" 2>/dev/null)
    if [[ -z "$mal_count" ]] || (( mal_count == 0 )); then
        return 0
    fi

    local found_malicious=0
    local found_any=0

    for ext_base in "${ext_base_dirs[@]}"; do
        # Each extension is a directory named by its ID (crx hash)
        while IFS= read -r -d '' manifest; do
            # The extension ID is the directory name two levels up from manifest.json
            local version_dir ext_dir
            version_dir="$(dirname "$manifest")"
            ext_dir="$(dirname "$version_dir")"
            local ext_id
            ext_id="$(basename "$ext_dir")"

            # Get extension name from manifest
            local ext_name
            ext_name=$(jq -r '.name // empty' "$manifest" 2>/dev/null | head -1)

            found_any=$(( found_any + 1 ))

            # Match by extension ID first (most reliable)
            local match_by_id
            match_by_id=$(jq -r --arg id "$ext_id" \
                '.extensions[] | select(.id == $id) | .name' "$data_file" 2>/dev/null | head -1)

            if [[ -n "$match_by_id" ]]; then
                log_fail "Malicious Chrome extension detected: \"${ext_name:-$ext_id}\" (ID: ${ext_id})"
                log_fail "  → Remove at chrome://extensions"
                audit_log "FAIL" "Malicious Chrome extension: ${ext_id} (${ext_name})"
                found_malicious=$(( found_malicious + 1 ))
                continue
            fi

            # Fallback: match by name (for extensions without known IDs)
            if [[ -n "$ext_name" ]]; then
                local match_by_name
                match_by_name=$(jq -r --arg name "$ext_name" \
                    '.extensions[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .name' \
                    "$data_file" 2>/dev/null | head -1)
                if [[ -n "$match_by_name" ]]; then
                    log_fail "Malicious Chrome extension detected: \"${ext_name}\" (ID: ${ext_id})"
                    log_fail "  → Remove at chrome://extensions"
                    audit_log "FAIL" "Malicious Chrome extension (name match): ${ext_name} (${ext_id})"
                    found_malicious=$(( found_malicious + 1 ))
                fi
            fi
        done < <(find "$ext_base" -name "manifest.json" -print0 2>/dev/null)
    done

    if (( found_malicious == 0 )); then
        if (( found_any > 0 )); then
            log_pass "No malicious Chrome extensions detected (${found_any} extensions checked)"
        else
            log_pass "No malicious Chrome extensions detected"
        fi
    fi

    return 0
}
