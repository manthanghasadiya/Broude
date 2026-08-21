# Security policy

## Report a vulnerability

If you find a security problem in Broude, email `manthan.ghasadiya@gmail.com`. Please do not open a public issue before we have had a chance to investigate it.

Include the affected version, a minimal reproduction, the impact you observed, and any suggested fix. Avoid sending real credentials or data that belongs to someone else.

We aim to acknowledge reports within 48 hours. That is a response target, not a guaranteed resolution time. We will coordinate disclosure with you after we understand the issue and have a fix or mitigation ready.

## Scope

Broude runs shell hooks on a developer's machine. Relevant reports include:

- code execution or command injection in a hook or installer
- unsafe changes to Claude Code settings
- rule or data-file poisoning
- bypasses for a documented blocking rule
- false positives that make normal development commands unusable

General feature requests, stale threat-intelligence entries, and undocumented pattern ideas can use the public issue tracker unless publishing them would create an immediate risk.

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |
| < 1.0   | No        |
