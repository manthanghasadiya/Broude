#!/usr/bin/env bash
# broude/uninstall.sh - Clean Broude removal
#
# Usage: bash uninstall.sh  (or bash ~/.broude/uninstall.sh)

set -euo pipefail

BROUDE_HOME="${HOME}/.broude"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

# ─── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

echo ""
echo -e "${BOLD}=== Broude Uninstaller ===${NC}"
echo ""

# ─── Step 1: Remove ~/.broude ─────────────────────────────────────────────────

if [[ -d "$BROUDE_HOME" ]]; then
    info "Removing ${BROUDE_HOME}..."
    rm -rf "$BROUDE_HOME"
    ok "Removed ${BROUDE_HOME}"
else
    info "~/.broude not found — skipping"
fi

# ─── Step 2: Remove broude hooks from Claude settings ────────────────────────

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    info "No Claude Code settings found at ${CLAUDE_SETTINGS} — nothing to clean"
else
    info "Removing Broude hooks from ${CLAUDE_SETTINGS}..."

    # Check if jq is available to do the merge
    if ! command -v jq &>/dev/null; then
        warn "jq not found — cannot auto-clean ${CLAUDE_SETTINGS}"
        warn "Manually remove any entries referencing ~/.broude/ from that file."
    else
        local_tmp=$(mktemp)

        # Remove hook entries that reference ~/.broude from SessionStart
        # Strategy: filter out any hook objects whose command contains ".broude/"
        jq '
          if .hooks.SessionStart then
            .hooks.SessionStart |= map(
              .hooks |= map(
                select(.command | (. == null) or (contains(".broude/") | not))
              ) |
              select(length > 0)
            ) |
            if (.hooks.SessionStart | length) == 0 then
              del(.hooks.SessionStart)
            else . end
          else . end
        ' "$CLAUDE_SETTINGS" > "$local_tmp"

        if [[ $? -eq 0 ]]; then
            cp "$local_tmp" "$CLAUDE_SETTINGS"
            ok "Broude hooks removed from ${CLAUDE_SETTINGS}"
        else
            warn "Could not cleanly remove hooks from ${CLAUDE_SETTINGS}"
            warn "Please manually remove entries referencing ~/.broude/"
        fi
        rm -f "$local_tmp"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}Broude has been removed.${NC}"
echo ""
echo "  Audit log (if any):  ~/.broude/audit.log was deleted along with ~/.broude/"
echo ""
