# Changelog

All notable changes to Broude will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
