[![CI](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml)

# RWM — Ruby Workspace Manager

An Nx-like monorepo tool for Ruby. Convention-over-configuration, zero runtime dependencies, delegates to Rake.

## What it does

RWM manages Ruby monorepos with multiple apps and libraries. It builds a dependency graph from your Gemfiles, enforces structural conventions, and runs tasks across packages in the right order.

**Conventions enforced:**
- Libraries live in `libs/`, applications in `apps/`
- Libs can depend on other libs. Apps can depend on libs.
- Apps cannot depend on other apps. Libs cannot depend on apps.
- No circular dependencies.

## Workspace structure

```
my-project/              # git root = workspace root
├── libs/
│   ├── auth/            # shared library
│   │   ├── Gemfile
│   │   ├── auth.gemspec
│   │   ├── Rakefile
│   │   └── lib/auth.rb
│   └── billing/
├── apps/
│   ├── api/             # application
│   └── web/
└── .rwm/                # generated state (gitignored)
    └── graph.json
```

The git root is the workspace root. `.rwm/` is created automatically to store generated state — add it to your `.gitignore`.

## Installation

Add to your Gemfile:

```ruby
gem "rwm"
```

Or install directly:

```sh
gem install rwm
```

Requires Ruby >= 3.1.0.

## Quick start

```sh
# Initialize a new workspace
rwm init

# Scaffold packages
rwm new lib auth
rwm new lib billing
rwm new app api

# Rebuild the dependency graph
rwm graph

# Validate conventions
rwm check

# List all packages
rwm list
```

## Commands

| Command | Description |
|---------|-------------|
| `rwm init` | Initialize a workspace: create dirs, Gemfile, Rakefile, update `.gitignore`, then bootstrap. Pass `--vscode` to generate a `.code-workspace` file. Idempotent. |
| `rwm bootstrap` | Install deps and run bootstrap tasks in root and all packages, build graph, install git hooks. Uses overcommit if `.overcommit.yml` is present, plain git hooks otherwise. Updates `.code-workspace` if it exists. |
| `rwm new <app\|lib> <name>` | Scaffold a new app or library with standard structure. Updates `.code-workspace` if it exists. |
| `rwm info <name>` | Show package details: type, path, dependencies, dependents. |
| `rwm graph` | Parse all Gemfiles, build the dependency DAG, save to `.rwm/graph.json`. Use `--dot` or `--mermaid` for visualization output. |
| `rwm check` | Validate the dependency graph against conventions. Exit 0 on success, 1 on failure. |
| `rwm list` | Print a table of all packages with their types, paths, and dependencies. |
| `rwm run <task> [package]` | Run a Rake task across all packages, or a single named package. |
| `rwm test [package]` | Shortcut for `rwm run test`. Also: `rwm spec`, `rwm build`. |
| `rwm affected` | Show packages affected by current changes (git diff + transitive dependents). |
| `rwm run <task> --affected` | Run a task only on affected packages and their dependents. |
| `rwm run <task> --no-cache` | Bypass automatic task caching. |
| `rwm help` | Show available commands and usage. |

## How dependencies work

RWM reads each package's `Gemfile` and extracts `path:` dependencies. These are mapped to known packages in the workspace to build a directed acyclic graph (DAG).

### Gemfile DSL

Scaffolded packages include `require "rwm/gemfile"` which adds the `rwm_lib` helper:

```ruby
# libs/billing/Gemfile
require "rwm/gemfile"

rwm_lib "auth"        # resolves to gem "auth", path: "<root>/libs/auth"
```

This replaces the verbose `gem "auth", path: "../../libs/auth"` pattern. The helper resolves the workspace root via git and builds the correct path automatically.

You can still use the raw `gem ... path:` syntax if you prefer — both work.

The graph is serialized to `.rwm/graph.json` and used for task ordering, affected detection, and convention checks.

## Bootstrap

`rwm bootstrap` is the "clone and go" command. After cloning a repo, run it to get fully set up:

1. `bundle install` in the workspace root
2. `rake bootstrap` in the root (if defined)
3. Install git hooks (`pre-push` runs `rwm check`, `post-commit` rebuilds graph on Gemfile changes). Uses overcommit if `.overcommit.yml` is present, plain git hooks otherwise.
4. `bundle install` + `rake bootstrap` in each package
5. Build and validate the dependency graph
6. Update `.code-workspace` (if it exists)

`rwm init` calls `bootstrap` automatically. Both are idempotent.

## Task caching

Tasks declared with `cacheable_task` in a package's Rakefile are automatically cached. When inputs haven't changed, the task is skipped.

```ruby
# libs/auth/Rakefile
require "rwm/rake"

cacheable_task :spec do
  sh "bundle exec rspec"
end

cacheable_task :build, output: "pkg/*.gem" do
  sh "gem build *.gemspec"
end
```

- **Automatic**: no flag needed — `rwm run spec` auto-detects cacheable tasks
- **Output verification**: if `output:` is declared, the cache re-runs the task when output files are missing
- **Transitive invalidation**: changing a dependency invalidates all dependents
- **Bypass**: use `--no-cache` to force re-execution

Non-cacheable tasks (plain `task`) always run.

## Design decisions

- **Zero runtime deps** — only Ruby stdlib and Bundler (ships with Ruby)
- **No config file** — the git root is the workspace root; `.rwm/` is generated state (gitignored)
- **Auto-detect base branch** — reads the remote default from git, no need to configure `main` vs `master` vs `develop`
- **Git hooks** — `pre-push` runs `rwm check`, `post-commit` rebuilds the graph. Uses overcommit if `.overcommit.yml` exists, plain git hooks otherwise
- **Parallel by default** — tasks run concurrently within each execution level
- **VSCode workspace** — opt-in via `rwm init --vscode`; once created, bootstrap and new keep it updated
- **Convention over configuration** — the directory layout _is_ the config

## Development

```sh
git clone https://github.com/sidbhatt11/ruby-workspace-manager.git
cd ruby-workspace-manager
bundle install
bundle exec rspec
```

## License

MIT
