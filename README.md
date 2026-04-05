[![CI](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/ruby_workspace_manager)](https://rubygems.org/gems/ruby_workspace_manager)
![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.2-red)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

# RWM — Ruby Workspace Manager

A monorepo tool for Ruby, inspired by [Nx](https://nx.dev). Convention-over-configuration, zero runtime dependencies, delegates to Rake.

RWM discovers packages in your repository, builds a dependency graph from Gemfiles, runs tasks in parallel respecting dependency order, detects which packages are affected by a change, and caches results so unchanged work is never repeated.

## Is this for me?

**RWM is a good fit if you are:**

- A Ruby team with **multiple apps sharing internal libraries** (auth, billing, notifications, etc.) and you want them in one repo with clear dependency boundaries, parallel test runs, and CI that only tests what changed.
- **Outgrowing a single Rails app** — you're extracting shared code into libraries that multiple apps consume, and you need a way to manage the dependencies between them without publishing private gems.
- Running **a few Rails apps that share domain logic** and you want one `git clone`, one `bootstrap` command, and a dependency graph that keeps everything honest.

**RWM is probably not for you if:**

- You have a single app with no shared libraries. A standard Rails/Ruby project doesn't need monorepo tooling.
- You need to publish packages to RubyGems or a private gem server as part of your workflow. RWM is a development and CI tool — it doesn't handle versioning or publishing.
- You need polyglot support (Ruby + JS + Go in one repo). Tools like [Bazel](https://bazel.build/) or [Nx](https://nx.dev) are better suited for that.
- You're already using Bundler path gems with a simple shell script and don't need caching, affected detection, or convention enforcement. RWM's value comes from those features — if you don't need them, you don't need RWM.

## Quick start

```sh
gem install ruby_workspace_manager

mkdir my-project && cd my-project
git init
rwm init                  # creates workspace structure, bootstraps everything

rwm new lib auth          # scaffold a library
rwm new lib billing
rwm new app api           # scaffold an application

rwm spec                  # runs `rake spec` in every package, in parallel
rwm spec --affected       # only packages changed on this branch
rwm spec auth billing     # only specific packages
```

## Core concepts

**Workspace** — A git repository containing multiple packages. The git root is the workspace root. No configuration file is needed; RWM finds the root via `git rev-parse --show-toplevel`.

**Package** — A directory inside `libs/` or `apps/` that contains a `Gemfile`. Each package is a self-contained Ruby gem with its own Gemfile, gemspec, Rakefile, and source code.

**Libraries** (`libs/`) — Shared code. Libraries can depend on other libraries but never on applications.

**Applications** (`apps/`) — Deployable units. Applications can depend on libraries but never on other applications.

**Dependency graph** — A directed acyclic graph (DAG) built by parsing each package's Gemfile for `path:` dependencies. This graph drives task ordering, affected detection, and convention checks. It is cached at `.rwm/graph.json` and auto-rebuilt when any Gemfile changes.

## Workspace layout

```
my-project/                # git root = workspace root
├── libs/
│   ├── auth/              # a library package
│   │   ├── Gemfile
│   │   ├── auth.gemspec
│   │   ├── Rakefile
│   │   └── lib/auth.rb
│   └── billing/
│       └── ...
├── apps/
│   ├── api/               # an application package
│   │   ├── Gemfile
│   │   ├── api.gemspec
│   │   ├── Rakefile
│   │   └── app/api.rb
│   └── web/
│       └── ...
├── Gemfile                # root Gemfile (rake, ruby_workspace_manager)
├── Rakefile               # root Rakefile (bootstrap task, etc.)
└── .rwm/                  # generated state (gitignored)
    ├── graph.json         # serialized dependency graph
    └── cache/             # task cache hashes
```

A directory is recognized as a package if it lives directly inside `libs/` or `apps/` and contains a `Gemfile`. Nested directories or directories without a Gemfile are ignored.

The `.rwm/` directory is created automatically and gitignored by `rwm init`. It stores the dependency graph cache and task cache state.

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Install, create packages, declare dependencies, build the graph |
| [Running Tasks](docs/running-tasks.md) | Parallel execution, output modes, failure handling, task caching |
| [Affected Detection](docs/affected-detection.md) | Change detection, root-level changes, base branch configuration |
| [Bootstrap](docs/bootstrap.md) | Workspace setup, the bootstrap rake task, daily workflow |
| [Conventions and Hooks](docs/conventions-and-hooks.md) | The three rules, git hooks, Overcommit integration |
| [Rails Integration](docs/rails-integration.md) | Zeitwerk, traditional vs compatible structure, `Rwm.require_libs` |
| [Command Reference](docs/command-reference.md) | All commands, flags, shell completions, VSCode integration |

## Design philosophy

**Zero runtime dependencies.** RWM depends only on Ruby's standard library and Bundler (which ships with Ruby). No Thor, no custom graph library — `TSort` from stdlib handles topological sorting. Installing RWM adds nothing to your dependency tree.

**No configuration file.** The git root is the workspace root. Libraries go in `libs/`, applications go in `apps/`. The dependency graph comes from Gemfiles. The conventions are the configuration.

**Delegation to Rake.** RWM does not invent a task system. It runs `bundle exec rake <task>` in each package. The Rakefile has full control over execution; RWM handles orchestration.

**Content-hash caching over timestamps.** The cache uses SHA256 content hashes rather than file timestamps. Timestamps change on branch switches and rebases. Content hashes are deterministic. This is the same model that [redo](https://cr.yp.to/redo.html) and [Bazel](https://bazel.build/) use.

## Resources

- **[Nx](https://nx.dev)** — The JavaScript monorepo tool that inspired RWM's workspace model, affected detection, and task caching.
- **[DJB's redo](https://cr.yp.to/redo.html)** — Build system that pioneered content-hash-based caching. RWM's task cache uses the same principle.
- **[Bazel](https://bazel.build/)** — Google's build tool. RWM borrows content-addressable caching but trades Bazel's complexity for convention-over-configuration.
- **[TSort](https://ruby-doc.org/stdlib/libdoc/tsort/rdoc/TSort.html)** — Ruby stdlib module implementing Tarjan's algorithm. Used for topological sorting and cycle detection.
- **[Bundler](https://bundler.io/)** — RWM reads Gemfiles using Bundler's DSL parser and relies on Bundler's dependency resolution at runtime.
- **[Overcommit](https://github.com/sds/overcommit)** — Git hook manager that RWM integrates with when present.
- **[Lerna](https://lerna.js.org/)** — The original JavaScript monorepo tool. RWM's `bootstrap` command is inspired by `lerna bootstrap`.
