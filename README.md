# Broude

One-line description: Your AI coding assistant's security watchdog.

## Logo placeholder
<!-- TODO: Add logo -->
[Leave a centered placeholder comment for the logo, we'll design it later]

## Badges
- CI status badge (GitHub Actions)
- License badge (MIT)
- Bash version badge (4.0+)

## What is Broude?
Broude is a set of Claude Code hooks that catch supply chain attacks, exposed secrets, and obfuscated bash commands before they hit your terminal. Think of it as a signature-based security layer that sits between your AI coding assistant and your shell.

## Why?
Supply chain attacks on developers have surged in recent years. In June 2026, malicious JetBrains plugins, rogue Chrome extensions, and compromised npm packages like Mastra were specifically crafted to steal developer credentials and disrupt AI agents. Broude protects you by auditing your environment during AI sessions.

## Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/manthanghasadiya/Broude/main/install.sh | bash
```

## What it checks
- Session audit: secrets, npm/pip deps, JetBrains plugins, Chrome extensions, git hooks
- [Coming soon] Pre-execution: malicious package installs, pipe-to-shell, GuardFall obfuscation
- [Coming soon] Post-execution: secret scanning in written files, audit trail

## Example Output
```text
=== BROUDE v1.0.0: Session Security Audit ===

Project: /path/to/project

[PASS] No secrets detected in project files (10 files scanned)
[PASS] .env is in .gitignore
[PASS] npm audit: no vulnerabilities found
[INFO] pip-audit skipped (no requirements.txt)
[PASS] JetBrains plugins look clean
[WARN] Found extensions matching known threats (PromptSnatcher variants): 'Chrome extension 1'

Risk: MEDIUM (4 PASS, 1 WARN, 0 FAIL)
Action: Address WARN items before committing.
==========================================
```

## Requirements
- bash 4.0+
- jq
- Claude Code
- Optional: npm (for dependency audit), pip-audit (for Python audit)

## Configuration
Customize Broude via `~/.broude/settings.json` (or project-local configuration) to bypass certain checks, add custom secret patterns, or toggle specific rules.

## Roadmap
- [v1.0](https://github.com/manthanghasadiya/Broude/issues/1): Session audit (current)
- [v1.1](https://github.com/manthanghasadiya/Broude/issues/2): Pre-execution blocking
- [v1.2](https://github.com/manthanghasadiya/Broude/issues/3): Post-execution scanning
- [v1.3](https://github.com/manthanghasadiya/Broude/issues/4): MCP server integration (mcpsec)
- [v1.4](https://github.com/manthanghasadiya/Broude/issues/5): AI-powered analysis

## Contributing
See CONTRIBUTING.md

## Author
Manthan Ghasadiya (@manthanghasadiya)
Built by the creator of mcpsec and 3 published CVEs in MCP servers.

## License
MIT
