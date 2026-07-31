# Changelog

All notable changes to Broude will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- BROUDE_VERSION stuck at 1.0.0, now correctly shows current version
- install.sh reads version dynamically from common.sh
- GitHub Actions pinned to SHA hashes (supply chain hardening)
- Phase 2 test suite now runs in CI
- Shellcheck warnings resolved (unused variable, unquoted expansion)
- Removed set -euo pipefail from install.sh for robustness

## [1.1.1] - 2026-07-25

### Added
- gf-a6 Empty Double-Quote Insertion detection pattern (`c""at`, `cu""rl`, etc.)
- gf-a7 Empty Single-Quote Insertion detection pattern (`c''at`, `cu''rl`, etc.)

### Fixed
- Hook crash handling: load_guardfall_patterns is safe from crashing the hook when `jq` is missing (fails open)

## [1.1.0] - 2026-07-24

### Added
- PreToolUse blocking hook (`pre-bash-check.sh`) for real-time command interception
- GuardFall obfuscation detection (5 classes, 25 patterns from Adversa AI research)
- Pipe-to-shell blocking (`curl`/`wget` piped to `bash`/`sh`/`python`/`node`)
- Dangerous command blocking (catastrophic/irreversible commands only)
- GuardFall checker library (`hooks/lib/guardfall-checker.sh`)
- Pipe/dangerous command checker library (`hooks/lib/pipe-checker.sh`)
- Comprehensive test suite for PreToolUse hook (50+ test cases, zero false positives)
- Allowlist for Broude's own install URL (exempt from pipe-to-shell blocking)


## [1.0.0] - 2026-07-24

### Added
- SessionStart hook (`session-audit.sh`) with security report card
- Secret detection engine with 20 patterns (AWS, OpenAI, GitHub, Stripe, etc.)
- npm dependency audit via `npm audit` delegation
- pip dependency audit via `pip-audit` delegation
- JetBrains malicious plugin detection (15 plugins from Aikido June 2026 research)
- Chrome malicious extension detection (12 PromptSnatcher extensions from MalExt Sentry June 2026)
- GuardFall obfuscation pattern database (5 classes, 25 patterns from Adversa AI research)
- Git security checks (suspicious hooks, tracked .env files)
- Audit logging to `~/.broude/audit.log`
- One-liner installer with merge-safe Claude Code settings integration
- Test suite with 8 integration tests
