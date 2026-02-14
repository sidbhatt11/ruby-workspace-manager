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
| `rwm init` | Initialize a workspace: create dirs, Gemfile, Rakefile, then bootstrap. Idempotent. |
| `rwm bootstrap` | Install deps and run bootstrap tasks in root and all packages, then build graph. |
| `rwm new <app\|lib> <name>` | Scaffold a new app or library with standard structure. |
| `rwm info <name>` | Show package details: type, path, dependencies, dependents. |
| `rwm graph` | Parse all Gemfiles, build the dependency DAG, save to `.rwm/graph.json`. |
| `rwm check` | Validate the dependency graph against conventions. Exit 0 on success, 1 on failure. |
| `rwm list` | Print a table of all packages with their types, paths, and dependencies. |

### Coming soon

| Command | Description |
|---------|-------------|
| `rwm run <task>` | Run a Rake task across all packages in parallel (by execution level). |
| `rwm test` | Shortcut for `rwm run test`. |
| `rwm affected` | Show packages affected by current changes (git diff). |
| `rwm run <task> --affected` | Run a task only on affected packages and their dependents. |

## How dependencies work

RWM reads each package's `Gemfile` and extracts `path:` dependencies. These are mapped to known packages in the workspace to build a directed acyclic graph (DAG).

```ruby
# libs/billing/Gemfile
gem "auth", path: "../../libs/auth"
```

This tells RWM that `billing` depends on `auth`. The graph is serialized to `.rwm/graph.json` and used for task ordering, affected detection, and convention checks.

## Bootstrap

`rwm bootstrap` is the "clone and go" command. After cloning a repo, run it to get fully set up:

1. `bundle install` in the workspace root
2. `rake bootstrap` in the root (if defined)
3. Set up overcommit hooks
4. `bundle install` + `rake bootstrap` in each package
5. Build and validate the dependency graph

`rwm init` calls `bootstrap` automatically. Both are idempotent.

## Design decisions

- **Zero runtime deps** — only Ruby stdlib and Bundler (ships with Ruby)
- **No config file** — the git root is the workspace root; `.rwm/` is generated state (gitignored)
- **Auto-detect base branch** — reads the remote default from git, no need to configure `main` vs `master` vs `develop`
- **Overcommit for git hooks** — `pre-push` runs `rwm check`, `post-commit` rebuilds the graph
- **Parallel by default** — tasks run concurrently within each execution level
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
