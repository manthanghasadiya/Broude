#!/usr/bin/env bash
# broude/hooks/lib/guardfall-checker.sh
#
# GuardFall obfuscation detection library.
# Loads patterns from guardfall-patterns.json and checks bash commands
# for obfuscation techniques documented by Adversa AI.
#
# Usage:
#   source hooks/lib/guardfall-checker.sh
#   load_guardfall_patterns "/path/to/guardfall-patterns.json"
#   result=$(check_guardfall "some command string")
#   if [[ -n "$result" ]]; then  # blocked
#
# DO NOT use set -e in this file — it will propagate to callers.

# ─── Internal state ──────────────────────────────────────────────────────────
# Parallel arrays populated by load_guardfall_patterns()
_GF_IDS=()
_GF_CLASS_IDS=()
_GF_CLASS_NAMES=()
_GF_NAMES=()
_GF_REGEXES=()
_GF_SEVERITIES=()
_GF_PATTERNS_LOADED=false

# Detect grep capability once at source time
_GF_GREP_CMD="grep -E"
if echo "" | grep -P "" 2>/dev/null; then
    _GF_GREP_CMD="grep -P"
fi

# ─── load_guardfall_patterns ─────────────────────────────────────────────────
# Parse guardfall-patterns.json into parallel arrays.
# Requires jq. Safe no-op if jq is missing or file not found.
# Usage: load_guardfall_patterns "/path/to/guardfall-patterns.json"
# Returns: 0 on success, 1 on failure.
load_guardfall_patterns() {
    local patterns_file="${1:-}"

    # Reset state
    _GF_IDS=()
    _GF_CLASS_IDS=()
    _GF_CLASS_NAMES=()
    _GF_NAMES=()
    _GF_REGEXES=()
    _GF_SEVERITIES=()
    _GF_PATTERNS_LOADED=false

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    if [[ -z "$patterns_file" ]] || [[ ! -f "$patterns_file" ]]; then
        return 1
    fi

    if ! jq empty "$patterns_file" 2>/dev/null; then
        return 1
    fi

    # Extract all patterns flat using jq — one line per field, tab-separated
    # Format: class_id\tclass_name\tpattern_id\tpattern_name\tregex\tseverity
    local raw_patterns
    raw_patterns=$(jq -r '
        .classes[] as $class |
        $class.patterns[] |
        [$class.id, $class.name, .id, .name, .regex, .severity] |
        @tsv
    ' "$patterns_file" 2>/dev/null) || return 1

    if [[ -z "$raw_patterns" ]]; then
        return 1
    fi

    # Parse into arrays
    while IFS=$'\t' read -r class_id class_name pat_id pat_name regex severity; do
        [[ -z "$regex" ]] && continue
        _GF_CLASS_IDS+=("$class_id")
        _GF_CLASS_NAMES+=("$class_name")
        _GF_IDS+=("$pat_id")
        _GF_NAMES+=("$pat_name")
        _GF_REGEXES+=("$regex")
        _GF_SEVERITIES+=("$severity")
    done <<< "$raw_patterns"

    if [[ ${#_GF_REGEXES[@]} -gt 0 ]]; then
        _GF_PATTERNS_LOADED=true
        return 0
    fi

    return 1
}

# ─── check_guardfall ──────────────────────────────────────────────────────────
# Test a command string against all loaded GuardFall patterns.
# Usage: result=$(check_guardfall "command string")
# Output (stdout): "CLASS_ID|CLASS_NAME|PATTERN_ID|PATTERN_NAME|SEVERITY" if match found
#                  Empty string if clean or patterns not loaded.
check_guardfall() {
    local cmd="${1:-}"

    # Empty command — nothing to check
    if [[ -z "${cmd// /}" ]]; then
        return 0
    fi

    # Patterns not loaded — fail open (allow)
    if [[ "$_GF_PATTERNS_LOADED" != "true" ]]; then
        return 0
    fi

    local i
    for (( i = 0; i < ${#_GF_REGEXES[@]}; i++ )); do
        local regex="${_GF_REGEXES[$i]}"
        local class_id="${_GF_CLASS_IDS[$i]}"
        local class_name="${_GF_CLASS_NAMES[$i]}"
        local pat_id="${_GF_IDS[$i]}"
        local pat_name="${_GF_NAMES[$i]}"
        local severity="${_GF_SEVERITIES[$i]}"

        # Try PCRE first, fall back to ERE
        local matched=false
        if [[ "$_GF_GREP_CMD" == "grep -P" ]]; then
            if echo "$cmd" | grep -qP "$regex" 2>/dev/null; then
                matched=true
            elif echo "$cmd" | grep -qE "$regex" 2>/dev/null; then
                matched=true
            fi
        else
            if echo "$cmd" | grep -qE "$regex" 2>/dev/null; then
                matched=true
            fi
        fi

        if [[ "$matched" == "true" ]]; then
            printf '%s|%s|%s|%s|%s\n' \
                "$class_id" "$class_name" "$pat_id" "$pat_name" "$severity"
            return 0
        fi
    done

    return 0
}
