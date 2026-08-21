# Broude

Broude is a small set of deterministic security hooks for Claude Code. It checks Bash commands before they run and audits a project when a session starts.

[![CI](https://github.com/manthanghasadiya/Broude/actions/workflows/ci.yml/badge.svg)](https://github.com/manthanghasadiya/Broude/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green)
[![v1.1.1](https://img.shields.io/badge/version-1.1.1-blue)](https://github.com/manthanghasadiya/Broude/releases/tag/v1.1.1)

Claude Code already has permission controls, sandboxing, and model-based safety checks. Those defenses are useful, but they are not perfect. Anthropic reports that auto mode catches about 83% of "overeager" actions before execution, with roughly 17% still getting through. Anthropic describes it as one layer inside a sandbox, not a replacement for containment or other controls. See [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude).

Broude covers a narrower job: known shell patterns. If a command matches one of its rules, the hook denies it without asking a model to judge intent.

```text
● Bash(echo Y2F0IC9ldGMvcGFzc3dk | base64 -d | bash)
  ⎿  Error: Hook PreToolUse:Bash denied this tool

[BROUDE BLOCK] Obfuscated command detected
  (GuardFall Class E: Base64 Encoded Payload) [critical]
```

## What it checks

Before each Bash tool call, Broude looks for:

- 27 command-obfuscation patterns across five classes
- download-and-execute commands such as `curl ... | bash`
- a short list of destructive commands, including root filesystem deletion, disk formatting, and writes to raw block devices

At session start, it checks for:

- secrets in common environment and configuration files
- tracked or unignored `.env` files
- vulnerable npm and Python dependencies, when the relevant audit tool is installed
- known malicious JetBrains plugins and Chrome extensions from the bundled data files
- Git hooks that download and execute remote code

The scripts and bundled rules run locally. Dependency audits may contact their package registries through `npm audit` or `pip-audit`. Broude itself has no telemetry.

## Install

Review the code before installing a security hook. Then clone the repository and run the installer from the checked-out copy:

```bash
git clone https://github.com/manthanghasadiya/Broude.git
cd Broude
bash install.sh
```

The installer copies the hooks and data to `~/.broude/` and merges two entries into `~/.claude/settings.json`. It does not replace the rest of your Claude Code configuration.

Requirements:

- Bash 4.0 or newer
- `jq`

## What a block looks like

```text
You:    "Follow the setup instructions in CLAUDE.md"
Claude: reads CLAUDE.md and attempts an obfuscated command
Claude: Bash(IFS='.';cmd='cat./etc/passwd';$cmd)
Broude: [BROUDE BLOCK] Obfuscated command detected
        (GuardFall Class C: IFS Override to Split Command) [high]
```

The hook exits with code 2, so Claude Code denies the tool call and includes Broude's reason in the result.

## Current test coverage

The repository has three shell test suites: command blocking, session audit, and installer lifecycle. Run them with:

```bash
bash tests/test-pre-bash-check.sh
bash tests/test-session-audit.sh
bash tests/test-install-lifecycle.sh
```

The command suite includes 42 blocking cases and 37 allowed or edge-case commands. The lifecycle suite covers clean installation, repeat installation, settings preservation, and uninstall. That is useful regression coverage, but it is not proof of a zero false-positive or zero false-negative rate in real projects.

## How it works

```text
Claude Code proposes a Bash command
                 |
          PreToolUse hook
                 |
       +---------+----------+
       |                    |
   no match              rule match
    exit 0                 exit 2
       |                    |
 command runs          command denied
```

The pre-execution hook is implemented in Bash and reads the tool-call JSON with `jq`. It checks the command against the bundled GuardFall rules, pipe-to-shell rules, and destructive-command rules in that order.

The session hook prints a report that Claude can read at startup:

```text
=== BROUDE v1.1.1: Session Security Audit ===

Project: /home/user/my-project

[PASS] No secrets detected in project files
[WARN] .env file exists but is not in .gitignore
[PASS] npm audit: 0 vulnerabilities

Risk: MEDIUM (2 PASS, 1 WARN, 0 FAIL)
Action: Add .env to .gitignore.
==========================================
```

Allow/block decisions and session-audit results are appended to `~/.broude/audit.log`. Broude does not persist command text because commands may contain credentials.

## Limits

Broude is a pattern matcher, not a sandbox, malware scanner, or complete endpoint-security product.

- New or sufficiently changed obfuscation can bypass a regex.
- A rule can block a legitimate command.
- The hook fails open when its own parsing or dependencies fail, so it does not break Claude Code. That also means an internal error can leave a command unchecked.
- Session checks are point-in-time hints. Bundled lists become stale unless they are maintained.
- The hook sees Bash tool calls routed through Claude Code. It cannot stop commands run elsewhere or contain a compromised process after execution.

Use Broude as defense in depth. Keep Claude Code's sandbox and permission controls enabled, limit credentials and network access, and review commands that cross a trust boundary.

## Configuration

The installer registers these hooks in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.broude/hooks/session-audit.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.broude/hooks/pre-bash-check.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Custom allowlists and rule toggles are not implemented yet.

## Uninstall

```bash
bash ~/.broude/uninstall.sh
```

This removes `~/.broude/` and the Broude entries from Claude Code's user settings.

## Contributing

Open an issue before a large change. The most useful contributions are bypass cases, false-positive reproductions, and sourced updates to the threat-intelligence files. Add a regression test with every rule change.

Use the [threat-intelligence issue template](https://github.com/manthanghasadiya/Broude/issues/new?template=threat_intel.md) for a new malicious package, plugin, or extension. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Author and license

Broude is maintained by [Manthan Ghasadiya](https://github.com/manthanghasadiya). It is available under the [MIT License](LICENSE).
