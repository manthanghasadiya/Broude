# Broude

**Broude** (bro + Claude) is a security layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that hooks into its lifecycle events to run automated security checks at session start.

Every time you open a Claude Code session, Broude audits your project and developer environment for common security issues — exposed secrets, vulnerable dependencies, and malicious IDE extensions — and injects a concise security report directly into Claude's context.

## Install

```bash
git clone https://github.com/your-org/broude ~/.broude-src
bash ~/.broude-src/install.sh
```

Requires: **bash**, **jq** (`brew install jq` / `apt install jq`)

## What Happens at Session Start

When you open Claude Code, Broude automatically:

1. **Scans for exposed secrets** — checks `.env`, `config.json`, `settings.py`, and other common files for API keys, tokens, and credentials using 20 well-known regex patterns
2. **Checks `.gitignore` coverage** — warns if `.env` files could accidentally be committed
3. **Audits npm dependencies** — delegates to `npm audit` and surfaces critical/high vulnerabilities
4. **Audits Python dependencies** — delegates to `pip-audit` if installed
5. **Checks JetBrains plugins** — cross-references installed plugins against 15 known malicious plugins (Aikido Security, June 2026)
6. **Checks Chrome extensions** — cross-references installed extensions against the PromptSnatcher campaign list (MalExt Sentry, June 2026)
7. **Inspects git hooks** — warns if any `.git/hooks/` scripts download and execute external code

## Example Output

```
=== BROUDE v1.0.0: Session Security Audit ===

Project: /home/user/my-project

[PASS] No secrets detected in project files
[WARN] .env file exists but is NOT in .gitignore — add '.env' to .gitignore
[PASS] npm audit: 0 vulnerabilities
[PASS] No malicious JetBrains plugins detected (12 plugins checked)
[WARN] Malicious Chrome extension detected: "Smart Adblocker Pro" (ID: jdoanlopeandhcclcgkijenjkghlooio)
       → Remove at chrome://extensions

Risk: MEDIUM (3 PASS, 2 WARN, 0 FAIL)
Action: Address WARN items before committing.
==========================================
```

Claude reads this report and adjusts its behavior accordingly — it will remind you to fix issues, refuse to commit secret files, and flag risky patterns.

## Design Principles

- **Pure bash + jq** — no Python, Node, or Docker. Works anywhere Claude Code runs.
- **No network calls in hooks** — all checks are local. The 10-second hook timeout is respected.
- **Never blocks session start** — always exits 0. Informational only.
- **Lean data files** — Broude doesn't maintain a malicious packages database. It delegates to `npm audit` and `pip-audit` for that. It only maintains small, stable, manually curated lists (secrets, obfuscation patterns, JetBrains plugins, Chrome extensions).

## Uninstall

```bash
bash ~/.broude/uninstall.sh
```

## License

MIT — see [LICENSE](LICENSE)
