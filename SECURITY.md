# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Broude itself, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, email: manthan.ghasadiya@gmail.com

You will receive a response within 48 hours. We will work with you to understand the issue and coordinate a fix before public disclosure.

## Scope

Broude is a local security tool that runs bash scripts on the developer's machine. Security concerns include:

- Hook scripts that could be exploited to execute arbitrary code
- Install script that could be manipulated (supply chain risk on Broude itself)
- Data file poisoning (malicious entries in threat intel files that cause false blocks)
- Bypass techniques that evade Broude's detection

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |
| < 1.0   | No        |
