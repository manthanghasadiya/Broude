#!/usr/bin/env bash
# broude/hooks/lib/pipe-checker.sh
#
# Pipe-to-shell and dangerous command detection library.
# Used by pre-bash-check.sh to block download-and-execute patterns
# and catastrophically destructive commands.
#
# Usage:
#   source hooks/lib/pipe-checker.sh
#   result=$(check_pipe_to_shell "some command")
#   result=$(check_dangerous_command "some command")
#
# DO NOT use set -e in this file — it propagates to callers.

# ─── Allowlisted URLs ─────────────────────────────────────────────────────────
# These URLs are trusted and exempt from pipe-to-shell blocking.
# ONLY Broude's own install URL is allowlisted.
_PIPE_ALLOWLIST=(
    "raw.githubusercontent.com/manthanghasadiya/Broude"
)

# ─── _is_allowlisted ─────────────────────────────────────────────────────────
# Check if a command matches the allowlist.
# Returns 0 (true) if allowlisted, 1 if not.
_is_allowlisted() {
    local cmd="$1"
    local entry
    for entry in "${_PIPE_ALLOWLIST[@]}"; do
        if [[ "$cmd" == *"$entry"* ]]; then
            return 0
        fi
    done
    return 1
}

# ─── check_pipe_to_shell ─────────────────────────────────────────────────────
# Detect download-and-execute patterns in a command string.
# Usage: result=$(check_pipe_to_shell "command string")
# Output (stdout): description string if a pattern matches, empty if clean.
check_pipe_to_shell() {
    local cmd="${1:-}"

    # Empty/whitespace only — clean
    if [[ -z "${cmd// /}" ]]; then
        return 0
    fi

    # Check allowlist first — if allowlisted, skip all checks
    if _is_allowlisted "$cmd"; then
        return 0
    fi

    # Pattern 1: Direct pipe to shell interpreter
    # curl/wget ... | bash/sh/zsh/python/python3/node/perl/ruby
    if echo "$cmd" | grep -qE \
        '(curl|wget)[[:space:]][^|]*\|[[:space:]]*(bash|sh|zsh|python[23]?|node|perl|ruby)' \
        2>/dev/null; then
        echo "downloading and executing remote code via pipe-to-shell"
        return 0
    fi

    # Pattern 2: wget -qO- ... | shell  (common one-liner form)
    if echo "$cmd" | grep -qE \
        'wget\s+-[qO]O?-?\s+[^|]+\|\s*(bash|sh|zsh|python[23]?|node)' \
        2>/dev/null; then
        echo "downloading and executing remote code via wget pipe-to-shell"
        return 0
    fi

    # Pattern 3: curl/wget -o /tmp/... && bash/sh /tmp/...
    # Download to temp file then execute it
    if echo "$cmd" | grep -qE \
        '(curl|wget)\s+.*(-[oO]|--output)\s+[/~][^&]+&&\s*(bash|sh|zsh|python[23]?)' \
        2>/dev/null; then
        echo "downloading to temp file then executing — staged pipe-to-shell"
        return 0
    fi

    # Pattern 4: bash <(curl ...) or sh <(wget ...) — process substitution fetch
    if echo "$cmd" | grep -qE \
        '(bash|sh|zsh)\s+<\(\s*(curl|wget)\s+' \
        2>/dev/null; then
        echo "executing remote script via process substitution"
        return 0
    fi

    # Pattern 5: source <(curl ...) or . <(wget ...)
    if echo "$cmd" | grep -qE \
        '(source|\.)\s+<\(\s*(curl|wget)\s+' \
        2>/dev/null; then
        echo "sourcing remote script via process substitution"
        return 0
    fi

    return 0
}

# ─── check_dangerous_command ─────────────────────────────────────────────────
# Detect catastrophically destructive commands.
# IMPORTANT: Keep this list SHORT. Only truly irreversible/system-destroying
# commands. Legitimate rm/chmod usage must NOT be blocked.
#
# Usage: result=$(check_dangerous_command "command string")
# Output (stdout): reason string if blocked, empty if clean.
check_dangerous_command() {
    local cmd="${1:-}"

    # Strip leading/trailing whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    cmd="${cmd%"${cmd##*[![:space:]]}"}"

    # Empty command — clean
    if [[ -z "$cmd" ]]; then
        return 0
    fi

    # ── rm -rf of root-level paths ────────────────────────────────────────────
    # rm -rf / OR rm -rf /* — wipes the entire filesystem
    if echo "$cmd" | grep -qE \
        'rm[[:space:]]+(-(r[a-zA-Z]*f|f[a-zA-Z]*r))[[:space:]]+/\*?([[:space:]]|$)' \
        2>/dev/null; then
        echo "rm -rf of root filesystem (/)  — would destroy the OS"
        return 0
    fi

    # rm -rf ~ or rm -rf $HOME — wipes the entire home directory
    if echo "$cmd" | grep -qE \
        'rm\s+(-[a-zA-Z]*f[a-zA-Z]*r|-[a-zA-Z]*r[a-zA-Z]*f)\s+(~|\$HOME)(\s|$)' \
        2>/dev/null; then
        echo "rm -rf of home directory — would destroy all user data"
        return 0
    fi

    # ── chmod -R 777 / — opens entire filesystem to all users ─────────────────
    if echo "$cmd" | grep -qE \
        'chmod\s+(-[a-zA-Z]*R[a-zA-Z]*|--recursive)\s+[0-7]*7[0-7]*7\s+(/\*?|/\s*$)' \
        2>/dev/null; then
        echo "chmod 777 of root filesystem (/) — removes all file permission controls"
        return 0
    fi

    # ── mkfs — formats a disk/partition ───────────────────────────────────────
    if echo "$cmd" | grep -qE \
        '^(sudo\s+)?mkfs(\.[a-z0-9]+)?\s+' \
        2>/dev/null; then
        echo "mkfs — formats a disk partition, destroys all data"
        return 0
    fi

    # ── dd to a raw block device (/dev/sd*, /dev/hd*, /dev/nvme*) ────────────
    if echo "$cmd" | grep -qE \
        'dd\s+.*\bof=/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|xvd[a-z]|vd[a-z])\b' \
        2>/dev/null; then
        echo "dd writing to raw block device — overwrites disk, destroys all data"
        return 0
    fi

    # ── dd if=/dev/zero or /dev/urandom to any /dev/ device ──────────────────
    if echo "$cmd" | grep -qE \
        'dd\s+.*if=/dev/(zero|urandom|random)\s+.*of=/dev/' \
        2>/dev/null; then
        echo "dd wiping raw device with /dev/zero or /dev/urandom"
        return 0
    fi

    # ── Fork bomb: :(){ :|:& };: ──────────────────────────────────────────────
    if echo "$cmd" | grep -qE \
        ':\(\)\s*\{.*:\s*\|.*:.*&.*\}' \
        2>/dev/null; then
        echo "fork bomb detected — would crash the system by exhausting process table"
        return 0
    fi

    # ── Redirect to raw block device (/dev/sda etc.) ─────────────────────────
    if echo "$cmd" | grep -qE \
        '>\s*/dev/(sd[a-z]|hd[a-z]|nvme[0-9])' \
        2>/dev/null; then
        echo "writing directly to raw block device — destroys disk data"
        return 0
    fi

    return 0
}
