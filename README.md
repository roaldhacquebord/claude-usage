# Claude Usage

A macOS menu bar app that shows your Claude subscription usage limits (current session, current
week, and per-model week) as `42% · 62% · 93%`. It gets the numbers by running Claude Code's own
`claude -p "/usage"`, so it needs no API token.

Requirements: macOS 14+, Xcode (only its toolchain is used), and Claude Code installed and logged in.

```bash
./build.sh install   # build, copy to /Applications, launch
./build.sh           # build only → build/Claude Usage.app
./test.sh            # run the tests
CLAUDE_USAGE_E2E=1 ./test.sh --filter realClaudeEndToEnd   # check against the real claude
```

Design: `docs/superpowers/specs/2026-09-11-claude-usage-menubar-design.md`
