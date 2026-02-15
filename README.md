[![CI](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.4-red)

# RWM — Ruby Workspace Manager

An Nx-like monorepo tool for Ruby. Convention-over-configuration, zero runtime dependencies, delegates to Rake.

## What it does

RWM manages Ruby monorepos with multiple apps and libraries. It builds a dependency graph from your Gemfiles, enforces structural conventions, runs tasks in parallel respecting dependency order, detects affected packages from git changes, and caches results so unchanged work is never repeated.

## Commands

| Command | Description |
|---------|-------------|
| `rwm init` | Initialize a workspace. |
| `rwm bootstrap` | Install deps, build graph, install hooks, run bootstrap tasks. |
| `rwm new <app\|lib> <name>` | Scaffold a new package. |
| `rwm graph` | Rebuild the dependency graph. `--dot` / `--mermaid` for visualization. |
| `rwm run <task> [pkg]` | Run a Rake task across packages. Packages without the task are skipped. |
| `rwm test` | Shortcut for `rwm run test`. Also: `rwm spec`, `rwm build`. |
| `rwm run <task> --affected` | Run only on packages affected by current changes. |
| `rwm check` | Validate conventions. |
| `rwm list` | List all packages. |
| `rwm info <name>` | Show package details. |
| `rwm affected` | Show affected packages. |
| `rwm cache clean [pkg]` | Clear cached task results. |

Shell completions for Bash and Zsh are included — see [GUIDE.md](GUIDE.md) for setup instructions.

See [GUIDE.md](GUIDE.md) for full usage documentation — dependencies, caching, affected detection, git hooks, design decisions, and more.

## License

MIT
