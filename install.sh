#!/usr/bin/env bash
# broude/install.sh - Broude installer
#
# Usage:
#   bash install.sh                   # Install from current directory
#   curl -fsSL https://... | bash     # One-liner (future)
#
# This script:
#   1. Copies broude to ~/.broude/
#   2. Makes all hook scripts executable
#   3. Checks jq is installed (warns if not)
#   4. Merges hook config into ~/.claude/settings.json (does NOT overwrite)
#   5. Runs a smoke-test of session-audit.sh
#   6. Prints a success summary

set -euo pipefail

BROUDE_HOME="${HOME}/.broude"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
INSTALL_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# ─── Step 1: Copy broude to ~/.broude ────────────────────────────────────────

header "=== Installing Broude v1.0.0 ==="
echo ""

info "Installing to ${BROUDE_HOME}..."

if [[ -d "$BROUDE_HOME" ]]; then
    warn "~/.broude already exists — updating in place"
fi

mkdir -p "$BROUDE_HOME"
cp -r "${INSTALL_SOURCE}/hooks"  "$BROUDE_HOME/"
cp -r "${INSTALL_SOURCE}/data"   "$BROUDE_HOME/"

# Copy uninstall script
cp "${INSTALL_SOURCE}/uninstall.sh" "$BROUDE_HOME/"

ok "Broude files copied to ${BROUDE_HOME}"

# ─── Step 2: Make scripts executable ─────────────────────────────────────────

info "Setting executable permissions..."
find "$BROUDE_HOME/hooks" -name "*.sh" -exec chmod +x {} \;
chmod +x "$BROUDE_HOME/uninstall.sh"
ok "All hook scripts are executable"

# ─── Step 3: Check for jq ────────────────────────────────────────────────────

info "Checking dependencies..."
if command -v jq &>/dev/null; then
    jq_version=$(jq --version 2>/dev/null || echo "unknown")
    ok "jq is installed (${jq_version})"
else
    warn "jq is NOT installed. Broude requires jq to function."
    warn "Install it before starting Claude Code:"
    echo ""
    echo "    macOS:  brew install jq"
    echo "    Ubuntu: sudo apt-get install -y jq"
    echo "    Fedora: sudo dnf install -y jq"
    echo "    Alpine: apk add jq"
    echo ""
fi

# ─── Step 4: Merge into Claude Code settings ─────────────────────────────────

header "Configuring Claude Code hooks..."

BROUDE_HOOK_ENTRY='{
  "type": "command",
  "command": "'"${BROUDE_HOME}/hooks/session-audit.sh"'",
  "timeout": 30
}'

mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    # No existing settings — create fresh
    info "Creating ${CLAUDE_SETTINGS}..."
    cat > "$CLAUDE_SETTINGS" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${BROUDE_HOME}/hooks/session-audit.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
EOF
    ok "Created ${CLAUDE_SETTINGS} with Broude hooks"
else
    # Existing settings — merge carefully
    info "Merging into existing ${CLAUDE_SETTINGS}..."

    # Check if broude hook is already registered
    if jq -e --arg cmd "${BROUDE_HOME}/hooks/session-audit.sh" \
        '.hooks.SessionStart[]?.hooks[]? | select(.command == $cmd)' \
        "$CLAUDE_SETTINGS" &>/dev/null; then
        ok "Broude hook already registered in Claude Code settings"
    else
        # Merge: add broude to SessionStart hooks array
        # We preserve all existing hooks and add ours as a new entry
        local_tmp=$(mktemp)
        jq --arg cmd "${BROUDE_HOME}/hooks/session-audit.sh" '
          # Ensure hooks.SessionStart exists
          .hooks.SessionStart //= [] |
          # Add broude as a new hook group at the end
          .hooks.SessionStart += [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": $cmd,
                  "timeout": 30
                }
              ]
            }
          ]
        ' "$CLAUDE_SETTINGS" > "$local_tmp"

        if [[ $? -eq 0 ]]; then
            cp "$local_tmp" "$CLAUDE_SETTINGS"
            ok "Broude hooks merged into ${CLAUDE_SETTINGS}"
        else
            err "Failed to merge into ${CLAUDE_SETTINGS} — your existing settings were NOT modified."
            err "Manually add the following to your settings.json:"
            echo ""
            cat "${INSTALL_SOURCE}/settings.json"
            echo ""
        fi
        rm -f "$local_tmp"
    fi
fi

# ─── Step 5: Smoke test ───────────────────────────────────────────────────────

header "Running smoke test..."

SMOKE_JSON='{"session_id":"install-test","type":"init","cwd":"'"${HOME}"'","timestamp":"2026-07-17T00:00:00Z"}'

if echo "$SMOKE_JSON" | bash "${BROUDE_HOME}/hooks/session-audit.sh" > /tmp/broude_smoke_test.out 2>&1; then
    ok "session-audit.sh ran successfully"
    echo ""
    echo "────────────────────────────────────────"
    cat /tmp/broude_smoke_test.out
    echo "────────────────────────────────────────"
    rm -f /tmp/broude_smoke_test.out
else
    warn "Smoke test exited with non-zero (this may be normal if jq is missing)"
    if [[ -s /tmp/broude_smoke_test.out ]]; then
        cat /tmp/broude_smoke_test.out
    fi
    rm -f /tmp/broude_smoke_test.out
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

header "=== Installation Complete ==="
echo ""
echo "  Broude is now active. The next time you start a Claude Code session,"
echo "  you'll see a security audit report at the top of the conversation."
echo ""
echo "  To uninstall:  bash ~/.broude/uninstall.sh"
echo ""
