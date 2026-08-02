# Broude

**Deterministic security hooks for Claude Code.**

<!-- Logo coming soon -->

[![CI](https://github.com/manthanghasadiya/Broude/actions/workflows/ci.yml/badge.svg)](https://github.com/manthanghasadiya/Broude/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green)
[![v1.1.1](https://img.shields.io/badge/version-1.1.1-blue)](https://github.com/manthanghasadiya/Broude/releases/tag/v1.1.1)

Claude Code is smart. It catches a lot of suspicious commands on its own. But smart is probabilistic. It depends on context, model version, attention, and how deep into a task the agent is. One missed prompt injection in a `postinstall` script or a poisoned `CLAUDE.md` is all it takes.

Broude is the deterministic layer. It pattern-matches every Bash command against 27 obfuscation signatures, pipe-to-shell patterns, and destructive command templates before the shell ever sees it. No LLM reasoning, no context window, no judgment calls. If the pattern matches, the command is blocked. Every time.

```
● Bash(echo Y2F0IC9ldGMvcGFzc3dk | base64 -d | bash)
  ⎿  Error: Hook PreToolUse:Bash denied this tool

[BROUDE BLOCK] Obfuscated command detected
  (GuardFall Class E: Base64 Encoded Payload) [critical]
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/manthanghasadiya/Broude/main/install.sh | bash
```

Installs to `~/.broude/`, merges hooks into `~/.claude/settings.json` without overwriting existing config. Requires `bash 4.0+` and `jq`.

## What happens when you use it

**On session start**, Broude scans your project environment and feeds a security report to Claude:

```
=== BROUDE v1.1.1: Session Security Audit ===

Project: /home/user/my-project

[PASS] No secrets detected in project files
[WARN] .env file exists but is not in .gitignore
[PASS] npm audit: 0 vulnerabilities
[PASS] No malicious JetBrains plugins detected
[INFO] Chrome: not installed, skipping extension check
[PASS] Git hooks look clean

Risk: MEDIUM (4 PASS, 1 WARN, 0 FAIL)
Action: Add .env to .gitignore.
==========================================
```

Claude reads this report and adjusts its behavior. It knows about the security issues before you even start working.

**On every command**, Broude intercepts Bash tool calls and blocks anything that matches an obfuscation or attack pattern:

```
You:    "Follow the setup instructions in CLAUDE.md"
Claude: reads CLAUDE.md, finds a "diagnostic" command
Claude: Bash(IFS='.';cmd='cat./etc/passwd';$cmd)
Broude: [BROUDE BLOCK] Obfuscated command detected
        (GuardFall Class C: IFS Override to Split Command) [high]
Claude: "Your security hook blocked this. The command uses IFS
        manipulation to disguise 'cat /etc/passwd'."
```

The command never reaches the shell. Claude sees why it was blocked and explains the technique to you.

## Detection coverage

**Tested against 19 obfuscation techniques. 15 blocked, 0 false positives.**

| Category | Technique | Severity | Status |
|----------|-----------|----------|--------|
| **GuardFall Class A** | Empty quote insertion (`c""at`) | High | Blocked |
| **GuardFall Class A** | Here-string eval | High | Blocked |
| **GuardFall Class B** | Variable substring extraction | Medium | Blocked |
| **GuardFall Class B** | Indirect variable reference | Medium | Blocked |
| **GuardFall Class B** | Tr-based ROT13 decode | High | Blocked |
| **GuardFall Class C** | IFS word-splitting bypass | High | Blocked |
| **GuardFall Class D** | Brace expansion command build | Medium | Blocked |
| **GuardFall Class E** | Base64 decode pipe to shell | Critical | Blocked |
| **GuardFall Class E** | Octal encoded command | High | Blocked |
| **GuardFall Class E** | Python exec with encoded string | Critical | Blocked |
| **GuardFall Class E** | Process substitution fetch | High | Blocked |
| **GuardFall Class E** | Curl/wget pipe to shell | Critical | Blocked |
| **Pipe-to-shell** | `curl \| bash`, `wget \| sh` variants | Critical | Blocked |
| **Dangerous** | `rm -rf /`, fork bombs, `dd` to disk | Critical | Blocked |

Zero false positives on `npm install`, `ls -la`, `git status`, `curl` (without pipe), `rm -rf node_modules/`, and 30+ other legitimate commands.

GuardFall obfuscation classes are based on [Adversa AI's research](https://adversa.ai) on bypassing AI coding agent safety layers (June 2026).

## How it works

```
You type a prompt
       |
Claude decides to run a bash command
       |
   PreToolUse hook fires
       |
   broude/hooks/pre-bash-check.sh receives the command as JSON
       |
   +---------------------------+
   | 1. GuardFall check        |  27 obfuscation patterns
   | 2. Pipe-to-shell check    |  download-and-execute patterns  
   | 3. Dangerous command check|  catastrophic/irreversible only
   +---------------------------+
       |              |
    CLEAN           MATCH
    exit 0          exit 2
       |              |
   Command         Command BLOCKED
   executes        Claude told why
```

Pure bash + jq. No network calls. No LLM inference. No external dependencies beyond jq. Every check runs in under 500ms.

## Session audit checks

On every session start, Broude scans for:

- **Exposed secrets** in `.env`, config files, and source code (20 patterns: AWS, OpenAI, GitHub, Stripe, Anthropic, Google, Slack, and more)
- **Vulnerable dependencies** via `npm audit` and `pip-audit` (delegated, no local database)
- **Malicious JetBrains plugins** (15 plugins from [Aikido Security](https://www.aikido.dev/) June 2026 research)
- **Malicious Chrome extensions** (12 PromptSnatcher variants from MalExt Sentry June 2026)
- **Git hook tampering** (scripts that download and execute remote code)
- **Unprotected .env files** (missing .gitignore coverage, git-tracked secrets)

Everything runs locally against flat data files. No API calls, no telemetry, no data leaves your machine.

## Configuration

Broude hooks are registered in `~/.claude/settings.json`. The installer handles this automatically, merging alongside any existing hooks.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{
          "type": "command",
          "command": "$HOME/.broude/hooks/session-audit.sh",
          "timeout": 30
        }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "$HOME/.broude/hooks/pre-bash-check.sh",
          "timeout": 10
        }]
      }
    ]
  }
}
```

User-level configuration file (`~/.broude/config.json`) for custom allowlists, pattern toggles, and sensitivity tuning is [planned](https://github.com/manthanghasadiya/Broude/issues).

## Audit log

Every blocked command and session audit result is logged to `~/.broude/audit.log`:

```
[2026-07-25T08:29:55Z] [BLOCK] pre-bash-check: GuardFall Class A (Empty Double-Quote Insertion) | cmd=c""at /etc/passwd
[2026-07-25T08:30:12Z] [ALLOW] pre-bash-check: command passed all checks | cmd=npm install express
[2026-07-25T08:30:45Z] [WARN] Secret in .env:1 | AWS Access Key ID | critical
```

## Roadmap

- [x] **v1.0** Session security audit ([#1](https://github.com/manthanghasadiya/Broude/issues/1))
- [x] **v1.1** Pre-execution blocking with GuardFall detection ([#2](https://github.com/manthanghasadiya/Broude/issues/2))
- [ ] **v1.2** Post-execution scanning: secret detection in written files ([#3](https://github.com/manthanghasadiya/Broude/issues/3))
- [ ] **v1.3** MCP server mode for agent-agnostic security ([#4](https://github.com/manthanghasadiya/Broude/issues/4))
- [ ] **v1.4** AI-powered hybrid analysis ([#5](https://github.com/manthanghasadiya/Broude/issues/5))

## Uninstall

```bash
bash ~/.broude/uninstall.sh
```

Removes `~/.broude/` and cleans Broude hooks from `~/.claude/settings.json`.

## Testing

```bash
# Run all tests
bash tests/test-session-audit.sh    # 32 tests
bash tests/test-pre-bash-check.sh   # 78 tests

# Test a specific command manually
echo '{"hook_event_name":"PreToolUse","session_id":"t","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"c\"\"at /etc/passwd"}}' | bash hooks/pre-bash-check.sh
```

110 tests, all passing, zero false positives.

## Contributing

Open an issue before submitting PRs. Contributions are especially welcome for:

- **New obfuscation patterns** for `data/guardfall-patterns.json`
- **Threat intel updates** for malicious plugins/extensions
- **Test cases** (both attacks that should be blocked and legitimate commands that should pass)
- **Bug reports** with reproduction steps

Use the [threat intel template](https://github.com/manthanghasadiya/Broude/issues/new?template=threat_intel.md) to report new malicious packages, plugins, or extensions.

## Background

In June 2026, three supply chain attack waves hit developer tooling simultaneously: [15 malicious JetBrains plugins](https://www.aikido.dev/) stealing API keys, [Chrome extensions harvesting LLM credentials](https://adversa.ai), and [140+ backdoored npm packages](https://socket.dev/) through the Mastra framework compromise. All of them targeted developers using AI coding assistants.

Broude exists because these attacks exploit a gap: AI agents are smart about reasoning but blind to threat intelligence. They don't maintain databases of known-bad packages, they can't pattern-match obfuscated shell commands deterministically, and they don't audit your IDE plugins. Broude fills that gap.

## Author

[Manthan Ghasadiya](https://github.com/manthanghasadiya) ([@manthanghasadiya](https://x.com/manthanghasadiya))

Security researcher and pentester. Creator of [mcpsec](https://github.com/manthanghasadiya/mcpsec), the first MCP server security scanner. 4 published CVEs in MCP server implementations ([CVE-2026-6942](https://nvd.nist.gov/vuln/detail/CVE-2026-6942), [CVE-2026-42449](https://nvd.nist.gov/vuln/detail/CVE-2026-42449), [CVE-2026-35394](https://nvd.nist.gov/vuln/detail/CVE-2026-35394), [CVE-2026-47427](https://nvd.nist.gov/vuln/detail/CVE-2026-47427)).

## License

[MIT](LICENSE)