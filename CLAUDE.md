# RWM — Ruby Workspace Manager

## Project Overview

An Nx-like monorepo tool for Ruby. Convention-over-configuration, zero runtime deps, delegates to Rake.

## Key Files

- `PLAN.md` — Full architecture and implementation plan. Read this first.
- `TODO.md` — Implementation checklist by phase.

## Conventions

- Ruby gem structure under `lib/rwm/`
- Zero runtime dependencies — only Ruby stdlib + Bundler
- CLI uses `OptionParser` (no Thor/GLI)
- Graph uses `TSort` from stdlib
- All specs in `spec/rwm/` using RSpec
- Gemspec requires Ruby >= 3.1.0
- No config file — `.rwm/` directory is the workspace root marker and holds all rwm state
- Overcommit for git hooks (not hand-rolled)

## Rules

- Never commit with GPG signing (`--no-gpg-sign`)
- Follow the phase order in TODO.md — core foundation first, then task runner, affected detection, overcommit
- Keep it simple — no over-engineering, no unnecessary abstractions
- When writing specs, use fixture monorepo structures in tmp dirs
