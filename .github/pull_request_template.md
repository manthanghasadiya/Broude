## What does this PR do?

Brief description.

## Type of change

- [ ] Bug fix
- [ ] New detection/check
- [ ] Threat data update
- [ ] Documentation
- [ ] CI/infrastructure

## Testing

- [ ] Tested on macOS
- [ ] Tested on Linux
- [ ] Tested on WSL
- [ ] Test suite passes (`bash tests/test-session-audit.sh`)
- [ ] Manual testing with real Claude Code session

## Checklist

- [ ] No network calls added to hook scripts
- [ ] Exit codes are correct (0 for allow/info, 2 for block)
- [ ] jq dependency check at top of new scripts
- [ ] Output is concise and human-readable (Claude will read it)
