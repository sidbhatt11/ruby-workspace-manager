# RWM Usage Guide

This guide explains how RWM works, why it makes the choices it does, and how to use it effectively.

## Table of Contents

- [What problem does RWM solve?](#what-problem-does-rwm-solve)
- [Core concepts](#core-concepts)
- [Getting started](#getting-started)
- [Bootstrap and daily workflow](#bootstrap-and-daily-workflow)
- [Workspace layout](#workspace-layout)
- [Managing packages](#managing-packages)
- [Dependencies between packages](#dependencies-between-packages)
- [The dependency graph](#the-dependency-graph)
- [Running tasks](#running-tasks)
- [Task caching](#task-caching)
- [Affected detection](#affected-detection)
- [Git hooks](#git-hooks)
- [Convention enforcement](#convention-enforcement)
- [VSCode integration](#vscode-integration)
- [Shell completions](#shell-completions)
- [Command reference](#command-reference)
- [Design philosophy](#design-philosophy)
- [Resources](#resources)

---

## What problem does RWM solve?

When a Ruby codebase grows, teams split it into multiple gems — shared libraries and applications that depend on each other. Without tooling, this creates friction:

- You `bundle install` in six directories after cloning.
- You change a library and forget to test the apps that depend on it.
- You run specs across all packages one by one, sequentially.
- There is no single source of truth for how packages relate to each other.

RWM provides a single command-line tool that understands your entire monorepo: it discovers packages, builds a dependency graph, runs tasks in parallel respecting dependency order, detects which packages are affected by a change, and caches results so unchanged work is never repeated.

Think of it as [Nx](https://nx.dev) for Ruby — but with zero runtime dependencies, no configuration file, and delegation to Rake for task execution.

## Core concepts

**Workspace** — A git repository containing multiple packages. The git root is the workspace root. No configuration file is needed to declare this; RWM finds the root by running `git rev-parse --show-toplevel`.

**Package** — A directory inside `libs/` or `apps/` that contains a `Gemfile`. Each package is a self-contained Ruby gem with its own Gemfile, gemspec, Rakefile, and source code.

**Libraries** (`libs/`) — Shared code packages. Libraries can depend on other libraries but never on applications.

**Applications** (`apps/`) — Deployable applications. Applications can depend on libraries but never on other applications.

**Dependency graph** — A directed acyclic graph (DAG) built by parsing each package's `Gemfile` for `path:` dependencies. This graph drives task ordering, affected detection, and convention checks. It is cached at `.rwm/graph.json` and auto-rebuilt when any Gemfile changes.

## Getting started

### Installation

Add RWM to your root Gemfile:

```ruby
gem "ruby_workspace_manager"
```

Or install globally:

```sh
gem install ruby_workspace_manager
```

### Initializing a workspace

```sh
mkdir my-project && cd my-project
git init
rwm init
```

`rwm init` creates the workspace structure:

- `libs/` and `apps/` directories
- A root `Gemfile` (with `gem "ruby_workspace_manager"`)
- A root `Rakefile` (with a `bootstrap` task)
- `.rwm/` added to `.gitignore`

It then runs `rwm bootstrap` automatically, which installs dependencies and sets up git hooks.

The command is idempotent — running it again on an existing workspace is safe and fills in anything missing.

### Creating your first packages

```sh
rwm new lib auth
rwm new lib billing
rwm new app api
```

Each command scaffolds a full gem structure. See [Managing packages](#managing-packages) for details on what's included.

### Declaring dependencies

Edit the consuming package's Gemfile to add a dependency:

```ruby
# apps/api/Gemfile
require "rwm/gemfile"

rwm_lib "auth"
rwm_lib "billing"
```

Then install and rebuild the graph:

```sh
cd apps/api && bundle install
rwm graph
```

### Running specs across everything

```sh
rwm test
```

This runs `rake test` in every package that has a `test` task, in dependency order, using all available CPU cores. Packages without the requested task are silently skipped.

## Bootstrap and daily workflow

### What bootstrap does

`rwm bootstrap` is the single command that gets a workspace into a working state. It:

1. Runs `bundle install` in the workspace root.
2. Runs `rake bootstrap` in the root (if defined — use this for binstubs, shared tooling, etc.).
3. Installs git hooks (`pre-push` runs `rwm check`, `post-commit` rebuilds the graph on Gemfile changes). Uses [Overcommit](https://github.com/sds/overcommit) if `.overcommit.yml` is present, plain git hooks otherwise.
4. Runs `bundle install` in every package (in parallel).
5. Runs `rake bootstrap` in packages that define it (in parallel).
6. Builds and validates the dependency graph.
7. Updates the `.code-workspace` file (if it exists).

`rwm init` calls `bootstrap` as its last step. Both commands are idempotent — safe to run repeatedly.

### The bootstrap rake task

Every scaffolded package includes an empty `bootstrap` task in its Rakefile. This is where package-specific setup logic belongs — anything beyond `bundle install` that a package needs to be ready for development:

```ruby
# libs/auth/Rakefile
task :bootstrap do
  sh "bin/rails db:setup" if File.exist?("bin/rails")
  sh "cp config/credentials.example.yml config/credentials.yml" unless File.exist?("config/credentials.yml")
end
```

Common examples:
- Database setup (`db:create`, `db:migrate`, `db:seed`)
- Copying example config files (`.env.example` to `.env`, example credentials)
- Generating local SSL certificates
- Compiling native extensions or protobuf definitions
- Seeding local caches or fixture data

The root Rakefile has a bootstrap task too — use it for workspace-wide setup like installing shared tooling, generating binstubs, or configuring git settings.

The key property: **`rwm bootstrap` runs every package's bootstrap task automatically.** Developers don't need to know which packages have special setup steps. They run one command and everything is handled. This is why writing your setup logic as a bootstrap task matters — it turns manual onboarding instructions into executable code that stays in sync with the codebase.

### After cloning

When a new developer joins the project:

```sh
git clone <repo>
cd <repo>
rwm bootstrap
```

That's it. Every package is installed, the dependency graph is built, git hooks are active, and the workspace is ready.

### Daily workflow

At the start of each working session, pull the latest changes and re-bootstrap:

```sh
git pull --rebase
rwm bootstrap
```

This ensures your local workspace reflects any packages that were added, removed, or had their dependencies changed by teammates. Bootstrap is idempotent and fast — it only does work where needed (Bundler skips already-installed gems, the graph rebuilds only if Gemfiles changed).

After bootstrapping, work on your feature branch as usual:

```sh
git checkout -b my-feature
# ... make changes ...
rwm test                        # run all specs
rwm run spec --affected         # or just the affected ones
```

Before pushing, `rwm check` runs automatically via the pre-push hook to validate conventions. If you've changed any Gemfiles, the post-commit hook rebuilds the graph automatically.

## Workspace layout

```
my-project/                # git root = workspace root
├── libs/
│   ├── auth/              # a library package
│   │   ├── Gemfile
│   │   ├── auth.gemspec
│   │   ├── Rakefile
│   │   └── lib/auth.rb    # libs use lib/ for source code
│   └── billing/
│       └── ...
├── apps/
│   ├── api/               # an application package
│   │   ├── Gemfile
│   │   ├── api.gemspec
│   │   ├── Rakefile
│   │   └── app/api.rb     # apps use app/ for source code
│   └── web/
│       └── ...
├── Gemfile                # root Gemfile (contains gem "ruby_workspace_manager")
├── Rakefile               # root Rakefile (bootstrap task, etc.)
└── .rwm/                  # generated state (gitignored)
    ├── graph.json         # serialized dependency graph
    └── cache/             # task cache hashes
```

A directory is recognized as a package if it lives directly inside `libs/` or `apps/` **and** contains a `Gemfile`. Nested directories or directories without a Gemfile are ignored.

The `.rwm/` directory is created automatically and should be gitignored. It stores the dependency graph cache and task cache state.

## Managing packages

### Scaffolding

```sh
rwm new lib <name>
rwm new app <name>
```

Package names must start with a lowercase letter and contain only lowercase letters, digits, and underscores (matching `/\A[a-z][a-z0-9_]*\z/`).

The scaffold includes:

- **Gemfile** — Sources from rubygems.org, loads the gemspec, includes `rake`, `rspec`, and `ruby_workspace_manager` as development/test dependencies, and requires `rwm/gemfile` for the `rwm_lib` helper.
- **Gemspec** — Minimal spec with package metadata. Libraries use `require_paths = ["lib"]` and declare `spec.files`; applications use `require_paths = ["app"]` and omit `spec.files` (apps are not distributed as gems).
- **Rakefile** — Uses `cacheable_task` from `rwm/rake` for the `:spec` task, plus an empty `:bootstrap` task for custom setup steps.
- **lib/<name>.rb** (libraries) or **app/<name>.rb** (applications) — Module stub. Libraries keep source code in `lib/`, applications keep source code in `app/`.
- **spec/spec_helper.rb** — Minimal RSpec configuration.

### Inspecting a package

```sh
rwm info auth
```

Outputs the package's type, path, dependencies, and direct/transitive dependents.

### Listing all packages

```sh
rwm list
```

Prints a formatted table of all packages with their types, relative paths, and dependency lists.

## Dependencies between packages

### How dependency detection works

RWM does not scan source code for `require` statements. Instead, it reads each package's `Gemfile` using Bundler's own DSL parser and extracts gems declared with a `path:` option. These paths are resolved to absolute paths and matched against known packages in the workspace.

This approach is deliberate: Bundler already manages load paths and dependency resolution. By reading Gemfiles, RWM uses the same source of truth that `bundle exec` uses at runtime. There is no second dependency system to keep in sync.

### The `rwm_lib` helper

Scaffolded packages include `require "rwm/gemfile"` in their Gemfile, which adds the `rwm_lib` method to Bundler's DSL:

```ruby
# libs/billing/Gemfile
require "rwm/gemfile"

rwm_lib "auth"
```

This expands to:

```ruby
gem "auth", path: "/absolute/path/to/libs/auth"
```

The workspace root is resolved via `git rev-parse --show-toplevel`, so it works regardless of where you run the command from. You can pass any extra options that `gem` accepts:

```ruby
rwm_lib "auth", require: false
```

There is no `rwm_app` helper. Applications are leaf nodes in the dependency graph — nothing should depend on them.

You can also use the raw `gem ... path:` syntax directly. Both work identically for dependency detection.

### Why only `path:` dependencies?

Gems from rubygems.org or git sources are external — they live outside the workspace and their code is not something RWM manages. Only `path:` dependencies represent intra-workspace relationships. This is the same model Bundler uses for workspace gems and the same approach Nx uses with TypeScript project references.

## The dependency graph

### Building the graph

```sh
rwm graph
```

This parses every package's Gemfile, constructs a DAG, writes it to `.rwm/graph.json`, and prints a summary. The graph is built using Ruby's `TSort` module (Tarjan's algorithm), which provides topological sorting and cycle detection from the standard library.

### Graph caching and staleness

Most commands (`run`, `list`, `check`, `affected`, `info`) load the graph from `.rwm/graph.json` rather than re-parsing every Gemfile. The cache includes an automatic staleness check: if any package's Gemfile has a modification time newer than the cache file, the graph is silently rebuilt and re-saved.

This means you rarely need to run `rwm graph` manually. It happens automatically when needed. The explicit command exists for when you want to force a rebuild or generate visualization output.

### Visualization

```sh
rwm graph --dot      # Graphviz DOT format
rwm graph --mermaid  # Mermaid flowchart format
```

Pipe DOT output to Graphviz to render an image:

```sh
rwm graph --dot | dot -Tpng -o graph.png
```

Or paste the Mermaid output into any Mermaid-compatible renderer (GitHub markdown, Mermaid Live Editor, etc.).

### The graph.json format

```json
{
  "version": 1,
  "generated_at": "2026-02-14T12:00:00-05:00",
  "packages": {
    "auth": { "name": "auth", "type": "lib", "path": "libs/auth" },
    "billing": { "name": "billing", "type": "lib", "path": "libs/billing" },
    "api": { "name": "api", "type": "app", "path": "apps/api" }
  },
  "edges": {
    "auth": [],
    "billing": ["auth"],
    "api": ["auth", "billing"]
  }
}
```

Paths are stored relative to the workspace root.

## Running tasks

### Basic usage

```sh
rwm run <task>              # run in all packages
rwm run <task> <package>    # run in one package
rwm test                    # shortcut for `rwm run test`
rwm spec                    # shortcut for `rwm run spec`
rwm build                   # shortcut for `rwm run build`
```

RWM runs `bundle exec rake <task>` in each package directory that has a Rakefile. Packages that don't define the requested task are detected automatically and silently skipped — they won't fail or cause their dependents to be skipped.

### How the DAG scheduler works

Tasks are not run sequentially or in simple "levels." RWM uses a DAG scheduler with a thread pool: each package starts executing the instant all of its dependencies have completed. If package A and B are independent, they run simultaneously. If C depends on A, C starts as soon as A finishes — it does not wait for B.

This eliminates idle time that level-based schedulers create when packages in the same level have very different durations.

The default concurrency is `Etc.nprocessors` (the number of CPU cores). Override it with:

```sh
rwm run spec --concurrency 4
```

### Output modes

**Streaming (default)** — Output is printed as it happens, prefixed with the package name:

```
[auth] 5 examples, 0 failures
[billing] 3 examples, 0 failures
```

This is the best mode for CI, where you want real-time feedback.

**Buffered** — Each package's output is collected and printed as a complete block when it finishes:

```
==> [auth]
5 examples, 0 failures

==> [billing]
3 examples, 0 failures
```

Failed packages have their output sent to stderr. Enable with:

```sh
rwm run spec --buffered
```

### Failure handling

When a package fails, all of its transitive dependents are immediately skipped — they can never satisfy their dependency requirements. But unrelated packages continue running normally. This maximizes useful work: if `auth` fails, `api` (which depends on `auth`) is skipped, but `notifications` (which is independent) still runs.

The exit code is 0 if all packages pass, 1 if any fail. Failed packages are listed in the summary output.

## Task caching

### Why caching matters

In a monorepo with many packages, most runs touch only a few packages. Without caching, `rwm run spec` re-runs every package's specs even if nothing changed. Task caching skips packages whose inputs are unchanged, potentially saving minutes on every run.

### The idea: content-hash caching from redo

RWM's cache is inspired by [DJB's redo](https://cr.yp.to/redo.html), a build system by Daniel J. Bernstein. The core insight of redo is: **use content hashes, not timestamps, to decide what needs rebuilding.** Timestamps are fragile — `git checkout` changes them, rebasing rewrites them, `touch` invalidates them. Content hashes are deterministic: if the bytes haven't changed, the hash hasn't changed, and the result is still valid. This is the same principle that [Bazel](https://bazel.build/) and [Nx](https://nx.dev) use.

### How it works

For each (package, task) pair, RWM:

1. **Computes a content hash** — SHA256 of all source files in the package (sorted by path for determinism), plus the content hashes of all dependency packages.
2. **Compares with stored hash** — If the hash matches the last successful run, and declared output files exist, the task is skipped.
3. **Stores on success** — After a successful run, the hash is saved to `.rwm/cache/<package>-<task>`.

Source files are discovered via `git ls-files` (tracked files plus untracked-but-not-ignored files), so anything in `.gitignore` is automatically excluded from the hash.

### Transitive invalidation

This is where the redo parallel is strongest. A package's content hash includes the content hashes of its dependencies, recursively:

```
hash(auth)    = SHA256(auth's files)
hash(billing) = SHA256(billing's files + hash(auth))
hash(api)     = SHA256(api's files + hash(billing) + hash(auth))
```

If you change a single file in `auth`, the hashes of `billing` and `api` change automatically — even though no file inside those packages was touched. Their caches are invalidated because their dependency changed. This cascades through the entire graph with no explicit invalidation logic.

This is exactly how redo's dependency chains work: a target that depends on another target inherits its staleness transitively. You never get a stale cache hit from a changed dependency.

### Where RWM is coarser than redo

True redo tracks **exactly which files a build step read** during execution (via filesystem-level interception). RWM hashes **every git-tracked file in the package directory**. This means:

- If you edit a README inside `libs/auth/`, the `spec` cache for `auth` is invalidated — even though RSpec never reads that file.
- If you add a comment to a non-required file, the cache busts.

This is a deliberate tradeoff. File-level read tracking would require intercepting filesystem calls (via `strace`, `dtrace`, or a FUSE layer), which contradicts the zero-dependency, keep-it-simple philosophy. Package-level hashing is coarser but **always correct** — it may give false invalidations (unnecessary re-runs), but never false cache hits (skipping when it shouldn't). For most Ruby packages, where source trees are small, the occasional extra re-run is cheap.

### Declaring cacheable tasks

Tasks are only cached if declared with `cacheable_task` in the package's Rakefile:

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

`cacheable_task` creates a normal Rake task — it works exactly like `task` when run directly via `rake spec`. The caching metadata is only used when RWM orchestrates the run.

The optional `output:` parameter declares a glob pattern for expected output files. If outputs are declared and the files don't exist, the cache is considered invalid even if the input hash matches. This handles the case where someone deletes build artifacts without changing source code.

Tasks declared with plain `task` (without `cacheable_task`) always run unconditionally.

### How RWM discovers cacheable tasks

Each package's Rakefile that uses `require "rwm/rake"` gets an automatic `rwm:cache_config` Rake task. When RWM prepares a run, it invokes `bundle exec rake rwm:cache_config` in each package to discover which tasks are cacheable and their output declarations. This output is JSON:

```json
{"spec": {}, "build": {"output": "pkg/*.gem"}}
```

### Bypassing the cache

```sh
rwm run spec --no-cache
```

This forces all tasks to run regardless of cache state. Useful when debugging or when you suspect the cache is stale (though the content-hash model makes false hits impossible — only false misses).

### Cache storage

The cache lives in `.rwm/cache/` — local and gitignored by default. Each cache entry is a single file named `<package>-<task>` containing the content hash string. Deleting `.rwm/cache/` is always safe; it just means the next run will re-execute everything.

### Sharing the cache across CI and developers

A cold cache means every run re-executes everything. In CI, that's the default — every job starts fresh. The fix is to persist the cache from your main branch and restore it on subsequent runs. Feature branch CI and local developers then inherit a warm cache where only their changes trigger re-runs.

**How it works:** Cache entries are content hashes with no absolute paths or machine-specific data. They're portable across machines. Restoring a stale cache is always safe — stale entries simply won't match the current content hash and the task re-runs. There's no risk of false cache hits, only harmless misses.

#### GitHub Actions

Use `actions/cache` to persist `.rwm/cache/` across CI runs:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true

      - name: Restore RWM cache
        uses: actions/cache@v4
        with:
          path: .rwm/cache
          key: rwm-${{ runner.os }}-${{ github.sha }}
          restore-keys: |
            rwm-${{ runner.os }}-

      - name: Run specs
        run: bundle exec rwm run spec --affected --committed
```

The `restore-keys` prefix match means feature branch runs restore the most recent cache from any prior run (typically from main). After the job, the cache is saved under the current SHA. Over time, this means:

- **Main branch CI** builds and saves a full cache after every merge.
- **Feature branch CI** restores main's cache, then only re-runs what the branch actually changed.
- **Subsequent runs on the same branch** restore their own cache from the previous push.

#### Local development

Locally, the cache warms itself: run `rwm test` once after cloning and subsequent runs skip unchanged packages. The CI cache strategy matters most for CI itself, where every job would otherwise start cold.

## Affected detection

### What "affected" means

When you change code on a feature branch, you typically want to know: which packages need to be tested? The answer is not just the packages you directly changed — it also includes every package that depends on them, transitively.

For example, if you change `libs/auth/`, and `libs/billing/` depends on `auth`, and `apps/api/` depends on `billing`, then all three are affected.

### Viewing affected packages

```sh
rwm affected
```

This shows the base branch, the number of affected packages, and a list with markers:

```
Base branch: main
Affected packages (3):

  auth (changed)
  billing (dependent)
  api (dependent)
```

### Running tasks on affected packages only

```sh
rwm run spec --affected
```

This is the most useful command for CI on feature branches. It combines affected detection with task execution: only affected packages are tested, and they run in the correct dependency order with full parallelism.

### How change detection works

RWM detects changes from three sources:

1. **Committed changes** — `git diff --name-only <base>...HEAD` (changes on the branch vs the base branch)
2. **Staged changes** — `git diff --name-only --cached` (changes added to the index but not yet committed)
3. **Unstaged changes** — `git diff --name-only` (working directory modifications)

Changed files are mapped to packages by path prefix. For example, `libs/auth/lib/auth.rb` maps to the `auth` package. Then the dependency graph is walked to find all transitive dependents.

**Root-level changes** (files outside any package directory, like the root `Gemfile` or `Rakefile`) cause all packages to be marked as affected. This is a conservative but safe default — root-level changes can affect the entire workspace.

Use `--committed` to ignore staged and unstaged changes, considering only what has been committed to the branch:

```sh
rwm run spec --affected --committed
```

### Base branch auto-detection

RWM does not hardcode `main` or `master`. It detects the base branch by:

1. Reading `git symbolic-ref refs/remotes/origin/HEAD` (the remote's default branch)
2. Falling back to checking if `main` or `master` exists as a local branch
3. Defaulting to `main` as a last resort

This works with any branching convention without configuration.

## Git hooks

RWM installs two git hooks during `rwm bootstrap` (and `rwm init`, which calls `bootstrap`):

- **pre-push** — Runs `rwm check` to validate conventions before pushing. Blocks the push if the dependency graph violates any rules.
- **post-commit** — Runs `rwm graph` (rebuild the dependency graph) if any Gemfile was changed in the commit. This keeps the cached graph in sync automatically.

### Overcommit integration

If your workspace has an `.overcommit.yml` file, RWM integrates with [Overcommit](https://github.com/sds/overcommit) instead of writing plain git hooks:

- Merges RWM hook configuration into `.overcommit.yml` (preserving your existing hooks)
- Creates executable hook scripts in `.git-hooks/pre_push/` and `.git-hooks/post_commit/`
- Runs `overcommit --install` and `overcommit --sign`

### Plain git hooks

Without Overcommit, RWM writes directly to `.git/hooks/`. It appends to existing hooks rather than overwriting them, so your custom hooks are preserved. The hooks are idempotent — running `bootstrap` again won't duplicate them.

## Convention enforcement

```sh
rwm check
```

Three rules are enforced:

1. **No library depending on an application.** Libraries are shared building blocks. If a library depends on an app, it becomes coupled to a deployment target, which defeats the purpose of extracting it.

2. **No application depending on another application.** Applications are independent deployment units. If one app depends on another, they should either be merged or the shared code should be extracted into a library.

3. **No circular dependencies.** Cycles make it impossible to determine build order and indicate tangled responsibilities.

`rwm check` exits 0 if all conventions pass, 1 if any are violated. The `pre-push` git hook runs this automatically, so violations are caught before code reaches the remote.

## VSCode integration

```sh
rwm init --vscode
```

This generates a `.code-workspace` file (named after the root directory) that configures VSCode's multi-root workspace feature. Each package becomes a separate root folder in the workspace, which means:

- Each package gets its own file tree in the sidebar
- Search scoping works per-package
- Extensions can be configured per-folder

The file is opt-in: `rwm init --vscode` creates it initially. After that, `rwm bootstrap` and `rwm new` keep the folder list updated automatically. Existing `settings`, `extensions`, `launch`, and `tasks` keys in the workspace file are preserved.

## Shell completions

RWM ships with completion scripts for Bash and Zsh. They provide command, flag, and package name completion.

### Bash

Add to your `.bashrc` or `.bash_profile`:

```bash
source "$(gem contents ruby_workspace_manager | grep rwm.bash)"
```

### Zsh

Add the completions directory to your `fpath` in `.zshrc` (before `compinit`):

```zsh
fpath=($(gem contents ruby_workspace_manager | grep completions/rwm.zsh | xargs dirname) $fpath)
autoload -Uz compinit && compinit
```

Both scripts dynamically discover package names by scanning `libs/` and `apps/` in the current workspace, so `rwm run spec <TAB>` and `rwm info <TAB>` complete with your actual package names.

## Command reference

| Command | Description |
|---------|-------------|
| `rwm init [--vscode]` | Initialize a workspace. Creates dirs, Gemfile, Rakefile, updates .gitignore, runs bootstrap. Idempotent. |
| `rwm bootstrap` | Install deps, build graph, install hooks, run bootstrap tasks in all packages. Idempotent. |
| `rwm new <app\|lib> <name>` | Scaffold a new package with standard structure. |
| `rwm info <name>` | Show package details: type, path, deps, dependents. |
| `rwm graph [--dot\|--mermaid]` | Rebuild dependency graph. Optionally output DOT or Mermaid format. |
| `rwm check` | Validate conventions. Exit 0 on pass, 1 on failure. |
| `rwm list` | Print a table of all packages. |
| `rwm run <task> [pkg]` | Run a Rake task across packages. Packages without the task are skipped. |
| `rwm test` | Shortcut for `rwm run test`. |
| `rwm spec` | Shortcut for `rwm run spec`. |
| `rwm build` | Shortcut for `rwm run build`. |
| `rwm affected [--committed] [--base REF]` | Show affected packages. |
| `rwm cache clean [pkg]` | Clear cached task results for one or all packages. |
| `rwm help` | Show available commands. |
| `rwm version` | Show version. |

### `rwm run` options

| Flag | Description |
|------|-------------|
| `--affected` | Only run on packages affected by current changes. |
| `--committed` | With `--affected`, only consider committed changes (ignore staged/unstaged). |
| `--base REF` | With `--affected`, compare against REF instead of auto-detected base branch. |
| `--dry-run` | Show what would run without executing. |
| `--no-cache` | Bypass task caching. Force all tasks to run. |
| `--buffered` | Buffer output per-package and print on completion. |
| `--concurrency N` | Limit parallel workers. Default: number of CPU cores. |

## Design philosophy

### Zero runtime dependencies

RWM depends only on Ruby's standard library and Bundler (which ships with Ruby). There is no Thor for CLI parsing — `OptionParser` from stdlib handles it. There is no custom graph library — `TSort` from stdlib implements Tarjan's algorithm. This means installing RWM adds nothing to your dependency tree beyond the gem itself.

### No configuration file

The git root is the workspace root. Libraries go in `libs/`, applications go in `apps/`. The dependency graph is derived from Gemfiles. There is nothing to configure because the conventions *are* the configuration.

This is a deliberate choice. Configuration files create a maintenance burden and a source of drift. By encoding the workspace structure in the directory layout and the dependency graph in Gemfiles (which Bundler already requires), RWM eliminates an entire class of "config is out of sync" problems.

### Delegation to Rake

RWM does not invent a task system. It delegates to Rake, which every Ruby project already uses. When RWM runs `bundle exec rake spec` in a package, the package's Rakefile has full control over what happens. RWM handles orchestration (ordering, parallelism, caching); Rake handles execution.

### Content-hash caching over timestamps

The task cache uses SHA256 content hashes rather than file timestamps. Timestamps are fragile — they change when you switch branches, rebase, or touch files without modifying them. Content hashes are deterministic: if the bytes haven't changed, the hash hasn't changed, and the cache is valid. This is the same model that [redo](https://cr.yp.to/redo.html) and [Bazel](https://bazel.build/) use. See [Task caching](#task-caching) for the full mechanics, including where RWM's approach is coarser than true redo-style file-level tracking and why that tradeoff is intentional.

<a id="future"></a>

## What's not here yet

- **Custom composite tasks** — Defining multi-step task pipelines beyond what Rake provides.
- **Watch mode** — Re-running affected tasks automatically when files change.

## Resources

- **[Nx](https://nx.dev)** — The JavaScript/TypeScript monorepo tool that inspired RWM's workspace model, affected detection, and task caching. If you've used Nx, RWM will feel familiar.
- **[DJB's redo](https://cr.yp.to/redo.html)** — Daniel J. Bernstein's build system that pioneered content-hash-based caching. RWM's task cache uses the same principle: hash inputs, skip if unchanged.
- **[Bazel](https://bazel.build/)** — Google's build tool. RWM borrows the idea of content-addressable caching and hermetic builds, but trades Bazel's complexity for convention-over-configuration.
- **[TSort](https://ruby-doc.org/stdlib/libdoc/tsort/rdoc/TSort.html)** — Ruby stdlib module implementing Tarjan's strongly connected components algorithm. RWM uses it for topological sorting and cycle detection in the dependency graph.
- **[Bundler](https://bundler.io/)** — RWM reads Gemfiles using Bundler's own DSL parser and relies on Bundler's dependency resolution at runtime. Understanding Bundler's `path:` source type is key to understanding how RWM detects dependencies.
- **[Overcommit](https://github.com/sds/overcommit)** — Git hook manager that RWM integrates with when present. Not required — RWM installs plain git hooks as a fallback.
- **[Lerna](https://lerna.js.org/)** — The original JavaScript monorepo tool. RWM's `bootstrap` command (install deps in all packages) is directly inspired by `lerna bootstrap`.
