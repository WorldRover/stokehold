# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Gemini CLI, and others) when working with code in this repository. It is the single source of truth for house style; `CLAUDE.md` and `GEMINI.md` are symlinks to it so each tool finds it under the name it looks for.

**GitHub:** [WorldRover/stokehold](https://github.com/WorldRover/stokehold)

## Project Overview

**stokehold** — a steampunk-maritime macOS menubar app that shows how hard Dan's machine is running under his AI agent fleet: brass pressure gauges for CPU/RAM/load, and the fleet itself rendered as "the black gang" stoking the boilers.

## Tech Stack

- Swift 6 / SwiftUI, `MenuBarExtra` (macOS 13+)
- Swift Package Manager, zero external dependencies
- No signing/notarization required for local `swift run` usage

## Commands

```bash
swift build   # compile
swift run     # launch the menubar app
```

## Versioning

Single version identifier — a `version` field in your project's manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, etc.) or a top-level `VERSION` file — kept in sync with the topmost released entry in `CHANGELOG.md`. For docs-only repos with no manifest, the CHANGELOG entry plus the git tag are the source of truth.

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — `## [version] - YYYY-MM-DD` headings with `### Added / Changed / Fixed / Removed` sections.

**Feature branches never touch `CHANGELOG.md`.** It is regenerated on the release PR from merged-PR titles, grouped by label.

**Cadence — buffer model.** Merged PRs accumulate on `main`; cut a release when the buffer is a meaningful chunk. No schedule; cuts are content-driven, not time-driven.

## Branches and pull requests

All changes land on a feature branch and merge to `main` via PR.

**Branch naming:** `<type>/<slug>` or `<type>/<issue>-<slug>`, lowercase and kebab-case:

- `feat/` — new user-visible capability
- `fix/` — bug fix
- `refactor/` — behavior-preserving code movement or restructuring
- `chore/` — tooling, deps, repo hygiene with no behavior change
- `docs/` — documentation only
- `test/` — test changes only

**PR labels:** every PR must have at least one label from the canonical scheme before merge.

**PR titles are plain descriptive text** — no conventional-commit prefix. Commit messages keep their `<type>:` prefix.

**Closing issues:** link resolved issues with `Closes #N` on its own line in the PR body.

## Labels

The canonical WorldRover label scheme (run `scripts/init-labels.sh` from a `wr-canon` clone to install it):

- **Domain:** `ui`, `data`, `infra`
- **Priority:** `P1`, `P2`, `P3`
- **Type:** `type: bug`, `type: feature`, `type: docs`, `type: enhancement`, `type: refactor`
- **Security:** `security`
- **Process:** `docs-skip`
- **Release:** `release`
- Plus the standard set: `duplicate`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`

## Key constants

- Fleet process names matched for "black gang" aggregation: `claude`, `codex`, `gemini`.
