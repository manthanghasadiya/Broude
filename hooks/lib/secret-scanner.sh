#!/usr/bin/env bash
# broude/hooks/lib/secret-scanner.sh - secret detection engine
# Source this file (do not execute directly).
# Requires: common.sh sourced first, jq available.

# ─── Pattern loading ──────────────────────────────────────────────────────────

# Parallel arrays holding loaded patterns
_SECRET_PATTERN_IDS=()
_SECRET_PATTERN_NAMES=()
_SECRET_PATTERN_REGEXES=()
_SECRET_PATTERN_SEVERITIES=()

# load_secret_patterns: load patterns from data/secret-patterns.json
# Usage: load_secret_patterns "/path/to/data/secret-patterns.json"
load_secret_patterns() {
    local data_file="${1:-}"
    if [[ -z "$data_file" ]] || [[ ! -f "$data_file" ]]; then
        echo "[BROUDE WARN] secret-patterns.json not found at: ${data_file}" >&2
        return 1
    fi

    # Read all patterns using jq, null-delimited fields
    local count
    count=$(jq '.patterns | length' "$data_file" 2>/dev/null)
    if [[ -z "$count" ]] || (( count == 0 )); then
        echo "[BROUDE WARN] No patterns found in ${data_file}" >&2
        return 1
    fi

    local i
    for (( i = 0; i < count; i++ )); do
        local id name regex severity
        id=$(jq -r ".patterns[$i].id" "$data_file")
        name=$(jq -r ".patterns[$i].name" "$data_file")
        regex=$(jq -r ".patterns[$i].regex" "$data_file")
        severity=$(jq -r ".patterns[$i].severity" "$data_file")
        _SECRET_PATTERN_IDS+=("$id")
        _SECRET_PATTERN_NAMES+=("$name")
        _SECRET_PATTERN_REGEXES+=("$regex")
        _SECRET_PATTERN_SEVERITIES+=("$severity")
    done
    return 0
}

# ─── Scanning helpers ─────────────────────────────────────────────────────────

# _run_pattern_on_file: run a single grep pattern against a file.
# Prints "filename:linenum:pattern_name" for each match.
_run_pattern_on_file() {
    local file="$1"
    local pattern_name="$2"
    local regex="$3"
    local severity="$4"

    # Use grep with perl-compatible regex where supported, fall back to extended
    local matches
    if grep -qP "" /dev/null 2>/dev/null; then
        matches=$(grep -nP "$regex" "$file" 2>/dev/null | head -5)
    else
        matches=$(grep -nE "$regex" "$file" 2>/dev/null | head -5)
    fi

    if [[ -n "$matches" ]]; then
        while IFS= read -r line; do
            local linenum
            linenum=$(echo "$line" | cut -d: -f1)
            echo "${file}:${linenum}:${severity}:${pattern_name}"
        done <<< "$matches"
    fi
}

# scan_file_for_secrets: scan a single file against all loaded patterns.
# Prints match lines: "file:line:severity:pattern_name"
# Returns 0 if any matches found, 1 if clean.
scan_file_for_secrets() {
    local file="$1"
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        return 1
    fi

    # Skip binary files
    if file "$file" 2>/dev/null | grep -q "binary"; then
        return 1
    fi

    local found=0
    local i
    for (( i = 0; i < ${#_SECRET_PATTERN_IDS[@]}; i++ )); do
        local result
        result=$(_run_pattern_on_file "$file" \
            "${_SECRET_PATTERN_NAMES[$i]}" \
            "${_SECRET_PATTERN_REGEXES[$i]}" \
            "${_SECRET_PATTERN_SEVERITIES[$i]}")
        if [[ -n "$result" ]]; then
            echo "$result"
            found=1
        fi
    done
    return $(( 1 - found ))
}

# scan_string_for_secrets: scan a string against all loaded patterns.
# Prints match lines: "line_num:severity:pattern_name"
# Returns 0 if any matches found, 1 if clean.
scan_string_for_secrets() {
    local input="$1"
    if [[ -z "$input" ]]; then
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/broude_scan_XXXXXX 2>/dev/null) || return 1
    echo "$input" > "$tmpfile"

    local found=0
    local i
    for (( i = 0; i < ${#_SECRET_PATTERN_IDS[@]}; i++ )); do
        local result
        result=$(_run_pattern_on_file "$tmpfile" \
            "${_SECRET_PATTERN_NAMES[$i]}" \
            "${_SECRET_PATTERN_REGEXES[$i]}" \
            "${_SECRET_PATTERN_SEVERITIES[$i]}")
        if [[ -n "$result" ]]; then
            # Strip the temp filename prefix from output
            echo "$result" | sed "s|${tmpfile}:|string:|g"
            found=1
        fi
    done

    rm -f "$tmpfile"
    return $(( 1 - found ))
}

# ─── .env / gitignore helpers ─────────────────────────────────────────────────

# check_env_in_gitignore: verify that .env files are covered by .gitignore.
# Usage: check_env_in_gitignore "/project/dir"
# Prints one of: "covered", "missing", "no_gitignore"
check_env_in_gitignore() {
    local project_dir="${1:-.}"
    local gitignore="${project_dir}/.gitignore"

    if [[ ! -f "$gitignore" ]]; then
        echo "no_gitignore"
        return
    fi

    # Check for common .env patterns in .gitignore
    if grep -qE '^\.env$|^\*\.env$|^\.env\*$|^\.env\..*$' "$gitignore" 2>/dev/null; then
        echo "covered"
    else
        echo "missing"
    fi
}

# check_git_tracked_secrets: check if any .env files are already tracked by git.
# Usage: check_git_tracked_secrets "/project/dir"
# Prints each tracked .env file path on its own line, or nothing if clean.
check_git_tracked_secrets() {
    local project_dir="${1:-.}"

    if [[ ! -d "${project_dir}/.git" ]]; then
        return 0
    fi

    # git ls-files lists tracked files; filter for .env variants
    (cd "$project_dir" && git ls-files 2>/dev/null) | \
        grep -E '(^|/)\.env(\.|$|\.local|\.production|\.development|\.test|\.staging)?' | \
        grep -v '^$' || true
}
