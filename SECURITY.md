# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in stokehold, please report it privately via [GitHub's vulnerability reporting](https://github.com/WorldRover/stokehold/security/advisories/new) rather than opening a public issue.

Include:

- Description of the vulnerability
- Steps to reproduce
- Affected version(s)

I'll acknowledge receipt within 7 days and aim to release a fix within 30 days for confirmed issues.

## Scope

The following are in scope:

- `Sources/` — application source code
- `Package.swift` — build configuration
- CI workflows in `.github/workflows/`

Out of scope:

- Third-party dependencies — report these to their maintainers via the relevant ecosystem's security channels.
- Local-only tooling (`.claude/`, `.vscode/`, etc.) — these run in trusted contexts.

## Known security considerations

stokehold shells out to `ps` to aggregate CPU/RAM for locally running `claude`/`codex`/`gemini` processes. It reads process names and resource usage only — no process arguments, environment variables, or file contents. It has no network access and persists no data.

## Past security fixes

None yet. This section will be populated as fixes land.
