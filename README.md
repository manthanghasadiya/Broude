# Broude

Your AI coding assistant's security watchdog.

<!-- Logo coming soon -->

[![CI](https://github.com/manthanghasadiya/Broude/actions/workflows/ci.yml/badge.svg)](https://github.com/manthanghasadiya/Broude/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green)

## What is Broude?
Broude is a set of Claude Code hooks that catch supply chain attacks, exposed secrets, and obfuscated bash commands before they hit your terminal. Think of it as a signature-based security layer that sits between your AI coding assistant and your shell.

## Why?
Supply chain attacks on developers have surged in recent years. In June 2026, malicious JetBrains plugins, rogue Chrome extensions, and compromised npm packages like Mastra were specifically crafted to steal developer credentials and disrupt AI agents. Broude protects you by auditing your environment during AI sessions.

## Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/manthanghasadiya/Broude/main/install.sh | bash
```

## What it checks
Broude performs a comprehensive session audit (checking for exposed secrets, npm/pip dependencies, malicious JetBrains plugins, suspicious Chrome extensions, and git hooks) and pre-execution command blocking (catching GuardFall obfuscation, pipe-to-shell patterns, and dangerous commands before execution). Post-execution scanning (for secret detection in written files and audit logging) is coming soon.

## Example Output
```text
=== BROUDE v1.1.1: Session Security Audit ===

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
Broude hooks are configured in ~/.claude/settings.json. A dedicated Broude configuration file for customizing checks is planned for a future release.

## Roadmap
- [v1.0](https://github.com/manthanghasadiya/Broude/issues/1): Session audit ✅
- [v1.1](https://github.com/manthanghasadiya/Broude/issues/2): Pre-execution blocking ✅
- [v1.2](https://github.com/manthanghasadiya/Broude/issues/3): Post-execution scanning (next)
- [v1.3](https://github.com/manthanghasadiya/Broude/issues/4): MCP server integration
- [v1.4](https://github.com/manthanghasadiya/Broude/issues/5): AI-powered analysis

## Contributing
Contributions welcome! Open an issue to discuss before submitting PRs.

## Author
Manthan Ghasadiya (@manthanghasadiya)
Built by the creator of mcpsec and 4 published CVEs in MCP servers.

## License
MIT
