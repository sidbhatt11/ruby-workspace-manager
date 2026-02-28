[![CI](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/sidbhatt11/ruby-workspace-manager/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/ruby_workspace_manager)](https://rubygems.org/gems/ruby_workspace_manager)
![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.2-red)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

# RWM — Ruby Workspace Manager

A monorepo tool for Ruby, inspired by [Nx](https://nx.dev). Convention-over-configuration, zero runtime dependencies, delegates to Rake.

RWM discovers packages in your repository, builds a dependency graph from Gemfiles, runs tasks in parallel respecting dependency order, detects which packages are affected by a change, and caches results so unchanged work is never repeated.

## Table of Contents

- [Getting started](#getting-started)
- [Core concepts](#core-concepts)
- [Workspace layout](#workspace-layout)
- [Managing packages](#managing-packages)
- [Dependencies between packages](#dependencies-between-packages)
- [The dependency graph](#the-dependency-graph)
- [Running tasks](#running-tasks)
- [Task caching](#task-caching)
- [Affected detection](#affected-detection)
- [Bootstrap and daily workflow](#bootstrap-and-daily-workflow)
- [Git hooks](#git-hooks)
- [Convention enforcement](#convention-enforcement)
- [Rails and Zeitwerk](#rails-and-zeitwerk)
- [VSCode integration](#vscode-integration)
- [Shell completions](#shell-completions)
- [Command reference](#command-reference)
- [Design philosophy](#design-philosophy)
- [Resources](#resources)

---

## Getting started

### New workspace

```sh
gem install ruby_workspace_manager

mkdir my-project && cd my-project
git init
rwm init
```

`rwm init` creates the full workspace structure — `libs/`, `apps/`, a root Gemfile (with `rake` and `ruby_workspace_manager`), a root Rakefile, and adds `.rwm/` to `.gitignore`. It then runs `rwm bootstrap` automatically. The command is idempotent.

### Existing project

If you already have a git repo with a Gemfile, add RWM to it and initialize:

```sh
bundle add ruby_workspace_manager
rwm init
```

`rwm init` won't overwrite your existing Gemfile or Rakefile — it only creates files that are missing.

### Creating packages

```sh
rwm new lib auth
rwm new lib billing
rwm new app api
```

Each command scaffolds a complete gem structure: Gemfile, gemspec, Rakefile, module stub, and test helper (unless `--test=none`).

### Declaring dependencies

Edit the consuming package's Gemfile:

```ruby
# apps/api/Gemfile
require "rwm/gemfile"

rwm_lib "auth"
rwm_lib "billing"
```

Then bootstrap to install deps and rebuild the graph:

```sh
rwm bootstrap
```

### Running tasks

```sh
rwm spec           # runs `rake spec` in every package that defines it
rwm lint           # any unrecognized command is a task shortcut
rwm lint auth      # run a task in a single package
```

Tasks run in parallel, respecting dependency order. Packages that don't define the requested task are silently skipped.

```
$ rwm spec
Running `rake spec` across 4 package(s)...

[auth] 12 examples, 0 failures
[billing] 8 examples, 0 failures
[notifications] 5 examples, 0 failures
[api] 21 examples, 0 failures

4 package(s): 4 passed.
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

## Managing packages

### Scaffolding

```sh
rwm new lib <name>
rwm new app <name>
rwm new lib <name> --test=minitest
rwm new app <name> --test=none
```

Package names must match `/\A[a-z][a-z0-9_]*\z/` (lowercase, letters/digits/underscores, starts with a letter).

The `--test` flag controls which test framework is scaffolded. Values: `rspec` (default), `minitest`, `none`.

The scaffold includes:

- **Gemfile** — Sources rubygems.org, loads the gemspec, includes development dependencies (`rake`, the chosen test gem, `ruby_workspace_manager`), and requires `rwm/gemfile` for the `rwm_lib` helper.
- **Gemspec** — Minimal spec. Libraries use `require_paths = ["lib"]` and declare `spec.files`; applications use `require_paths = ["app"]` and omit `spec.files`.
- **Rakefile** — A `cacheable_task` for the test framework (`:spec` for rspec, `:test` for minitest) plus an empty `:bootstrap` task. With `--test=none`, only the bootstrap task is generated.
- **Source file** — `lib/<name>.rb` for libraries, `app/<name>.rb` for applications. Module stub.
- **Test helper** — `spec/spec_helper.rb` for rspec, `test/test_helper.rb` for minitest. Omitted with `--test=none`.

### Inspecting and listing

```sh
rwm info auth     # type, path, dependencies, direct/transitive dependents
rwm list          # formatted table of all packages
```

## Dependencies between packages

### How dependency detection works

RWM reads each package's Gemfile using Bundler's DSL parser and extracts gems declared with a `path:` option pointing into the workspace. It does not scan source code for `require` statements. This means Bundler's Gemfile is the single source of truth for both runtime resolution and RWM's dependency graph.

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

The workspace root is resolved via `git rev-parse --show-toplevel`, so it works regardless of where you run the command. You can pass any extra options that `gem` accepts:

```ruby
rwm_lib "auth", require: false
```

There is no `rwm_app` helper. Applications are leaf nodes — nothing should depend on them.

`rwm_lib` validates that the library directory exists. If you reference a library that hasn't been created yet, you'll get a clear error:

```
rwm_lib 'payments': no library found at libs/payments.
Libraries must live in libs/. Create one with: rwm new lib payments
```

You can also use raw `gem ... path:` syntax directly. Both work identically for dependency detection.

### Transitive resolution

When you call `rwm_lib "auth"`, RWM automatically resolves auth's own workspace dependencies. If auth's Gemfile declares `rwm_lib "core"`, then `core` is added to your bundle automatically.

This works recursively. Diamond dependencies and cycles are handled safely (each lib is resolved at most once).

```ruby
# apps/web/Gemfile — only the direct dep is needed
require "rwm/gemfile"

rwm_lib "auth"    # core (auth's dep) is added automatically
```

Transitive resolution uses `Bundler::Dsl.eval_gemfile` — the same mechanism Bundler uses internally. Options passed to the direct `rwm_lib` call (like `group:` or `require:`) are not forwarded to transitive deps.

## The dependency graph

### Building

```sh
rwm graph
```

Parses every package's Gemfile, constructs a DAG using Ruby's `TSort` module (Tarjan's algorithm), writes it to `.rwm/graph.json`, and prints a summary.

### Caching and staleness

Most commands (`run`, `list`, `check`, `affected`, `info`) load the graph from `.rwm/graph.json` rather than re-parsing Gemfiles. If any package's Gemfile has a modification time newer than the cache file, the graph is silently rebuilt. You rarely need to run `rwm graph` manually.

Concurrent `rwm` processes are safe — graph reads use shared file locks and writes use exclusive file locks.

### Visualization

```sh
rwm graph --dot      # Graphviz DOT format
rwm graph --mermaid  # Mermaid flowchart format
```

Pipe DOT output to Graphviz to render an image:

```sh
rwm graph --dot | dot -Tpng -o graph.png
```

Or paste Mermaid output into any Mermaid-compatible renderer (GitHub markdown, Mermaid Live Editor, etc.).

## Running tasks

### Basic usage

```sh
rwm run <task>              # run in all packages
rwm run <task> <package>    # run in one package
rwm spec                    # shortcut for `rwm run spec`
rwm lint auth               # shortcut for `rwm run lint auth`
```

Any command that isn't a built-in subcommand is treated as a task name and forwarded to `rwm run`.

RWM runs `bundle exec rake <task>` in each package directory that has a Rakefile. Packages that don't define the requested task are automatically detected and silently skipped.

### Parallel execution

RWM uses a DAG scheduler with a thread pool. Each package starts executing the instant all of its dependencies have completed. If A and B are independent, they run simultaneously. If C depends on A, C starts as soon as A finishes — it does not wait for B.

The default concurrency is `Etc.nprocessors` (number of CPU cores). Override with:

```sh
rwm run spec --concurrency 4
```

### Output modes

**Streaming (default)** — Output is printed as it happens, prefixed with the package name:

```
[auth] 5 examples, 0 failures
[billing] 3 examples, 0 failures
```

**Buffered** — Each package's output is collected and printed as a complete block when it finishes. Failed packages have their output sent to stderr:

```sh
rwm run spec --buffered
```

### Failure handling

When a package fails, its transitive dependents are immediately skipped. Unrelated packages continue running. The exit code is 0 if all packages pass, 1 if any fail.

The summary distinguishes between skip reasons:

```
5 package(s): 2 passed, 1 failed, 1 skipped (dep failed), 1 skipped (no task).
```

- **skipped (dep failed)** — a dependency failed, so this package was not attempted
- **skipped (no task)** — the package's Rakefile doesn't define the requested task

## Task caching

### Why caching matters

In a monorepo with many packages, most runs touch only a few. Without caching, `rwm spec` re-runs everything even if nothing changed. Task caching skips packages whose inputs are unchanged.

### Content-hash caching

RWM's cache is inspired by [DJB's redo](https://cr.yp.to/redo.html). The core insight: **use content hashes, not timestamps, to decide what needs rebuilding.** Timestamps are fragile — `git checkout` changes them, rebasing rewrites them. Content hashes are deterministic: if the bytes haven't changed, the result is still valid.

For each (package, task) pair, RWM:

1. **Computes a content hash** — SHA256 of all source files in the package (sorted by path), plus the content hashes of all dependency packages.
2. **Compares with stored hash** — If the hash matches the last successful run and declared outputs exist, the task is skipped.
3. **Stores on success** — After a successful run, the hash is saved to `.rwm/cache/<package>-<task>`.

Source files are discovered via `git ls-files` (tracked + untracked-but-not-ignored), so anything in `.gitignore` is excluded from the hash.

### Transitive invalidation

A package's content hash includes the content hashes of its dependencies, recursively:

```
hash(auth)    = SHA256(auth's files)
hash(billing) = SHA256(billing's files + hash(auth))
hash(api)     = SHA256(api's files + hash(billing) + hash(auth))
```

Change a single file in `auth` and the hashes of `billing` and `api` change automatically. No explicit invalidation logic needed.

### Where the cache is coarser than redo

True redo tracks exactly which files a build step read during execution. RWM hashes every git-tracked file in the package directory. This means editing a README invalidates the spec cache even though RSpec never reads it.

This is a deliberate tradeoff. File-level read tracking would require filesystem interception (`strace`, `dtrace`, FUSE), which contradicts the zero-dependency philosophy. Package-level hashing may give false invalidations (unnecessary re-runs) but never false cache hits (skipping when it shouldn't).

### Declaring cacheable tasks

Tasks are only cached if declared with `cacheable_task` in the Rakefile:

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

`cacheable_task` creates a normal Rake task — it works like `task` when run directly. The caching metadata is only used when RWM orchestrates the run.

The optional `output:` parameter declares a glob for expected output files. If declared outputs don't exist, the cache is invalid even if the input hash matches.

Tasks declared with plain `task` always run unconditionally.

### Bypassing the cache

```sh
rwm run spec --no-cache
```

### Sharing the cache

The `.rwm/` directory is gitignored by design — committing it would create constant merge conflicts as the cache and graph change with every task run. Instead, treat your main branch CI as the single source of truth and distribute the cache from there.

Cache entries are content hashes with no absolute paths or machine-specific data. They're fully portable across machines. Restoring a stale cache is always safe — stale entries won't match and the task simply re-runs.

**The pattern:**

1. Main branch CI runs the full test suite, producing a complete `.rwm/` cache.
2. Feature branch CI restores main's cache, then runs only `--affected` packages.
3. Developer machines download the cache during `rwm bootstrap`, so new branches start pre-warmed.

The result: feature branch CI and local development only run what actually changed.

#### GitHub Actions

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Fetch base branch for affected detection
        if: github.ref != 'refs/heads/main'
        run: git fetch origin main --depth=1

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true

      - name: Restore RWM cache
        uses: actions/cache@v4
        with:
          path: .rwm
          key: rwm-${{ runner.os }}-${{ github.sha }}
          restore-keys: rwm-${{ runner.os }}-

      - name: Bootstrap
        run: bundle exec rwm bootstrap

      - name: Run specs
        run: |
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            bundle exec rwm run spec
          else
            bundle exec rwm run spec --affected
          fi

      # Make cache available for local dev bootstrap
      - name: Upload RWM cache
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: rwm-cache
          path: .rwm/
          retention-days: 30
```

Key points:

- **Fetch base branch** — Affected detection runs `git diff main...HEAD`, which needs the base branch ref. A shallow fetch of `main` is enough — no need for `fetch-depth: 0` or a full clone.
- **`actions/cache`** — Caches created on the default branch are accessible to all feature branches. The `restore-keys` prefix picks up the most recent main cache automatically.
- **Main runs everything**, populating a complete cache. Feature branches run only `--affected` and skip anything already cached from main.
- **`upload-artifact`** on main makes the cache downloadable for local dev bootstrap (see below).

#### Local developer cache (optional)

Add a cache download step to your root Rakefile so `rwm bootstrap` warms the local cache automatically:

```ruby
# Rakefile
task :bootstrap do
  restore_rwm_cache
end

def restore_rwm_cache
  return if File.directory?(".rwm/cache")
  return unless system("which gh > /dev/null 2>&1")

  puts "Downloading RWM cache from CI..."
  run_id = `gh run list --branch main --status success --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId'`.strip
  if run_id.empty?
    puts "No CI cache found. Skipping."
    return
  end

  system("gh", "run", "download", run_id, "--name", "rwm-cache", "--dir", ".rwm")
  puts File.directory?(".rwm/cache") ? "Cache restored." : "Cache download failed. Continuing without cache."
end
```

The example above uses the [GitHub CLI](https://cli.github.com/) (`gh`) to download artifacts — your setup may look different depending on your CI provider or storage backend (S3, GCS, etc.). The idea is the same: download the `.rwm/` directory from a known location during bootstrap.

After cloning and running `rwm bootstrap`, developers have a warm cache. Creating a feature branch from main and running `rwm run spec --affected` skips unchanged packages immediately.

## Affected detection

### What "affected" means

When you change code on a feature branch, the affected packages are those you directly changed plus every package that depends on them, transitively. If you change `libs/auth/` and `libs/billing/` depends on `auth` and `apps/api/` depends on `billing`, all three are affected.

### Viewing affected packages

```sh
rwm affected
```

### Running tasks on affected packages

```sh
rwm run spec --affected
```

This is the most useful command for feature branch CI. It combines affected detection with task execution — only affected packages are tested, in correct dependency order with full parallelism.

### How change detection works

RWM detects changes from three sources:

1. **Committed changes** — `git diff --name-only <base>...HEAD`
2. **Staged changes** — `git diff --name-only --cached`
3. **Unstaged changes** — `git diff --name-only`

Changed files are mapped to packages by path prefix. Use `--committed` to only consider committed changes (ignoring staged and unstaged):

```sh
rwm run spec --affected --committed
```

### Root-level changes

Files outside any package directory (like the root `Gemfile` or `Rakefile`) cause all packages to be marked as affected. This is a conservative default — root-level changes can affect the entire workspace.

However, inert files are automatically excluded from triggering a full run. The following patterns are ignored by default:

- `*.md`, `LICENSE*`, `CHANGELOG*`
- `.github/**`, `.vscode/**`, `.idea/**`
- `docs/**`, `.rwm/**`

You can add custom patterns in `.rwm/affected_ignore` (one glob per line, `#` for comments).

### Base branch auto-detection

RWM detects the base branch by reading `git symbolic-ref refs/remotes/origin/HEAD`, falling back to checking for `main` or `master` locally. Override with:

```sh
rwm affected --base develop
rwm run spec --affected --base develop
```

If the provided `--base` ref doesn't exist, RWM errors immediately instead of silently returning no affected packages.

## Bootstrap and daily workflow

### What bootstrap does

`rwm bootstrap` gets a workspace into a working state:

1. Runs `bundle install` in the workspace root.
2. Runs `rake bootstrap` in the root (if defined — for binstubs, shared tooling, etc.).
3. Installs git hooks (pre-push runs `rwm check`, post-commit rebuilds the graph on Gemfile changes).
4. Runs `bundle install` in every package (in parallel).
5. Runs `rake bootstrap` in packages that define it (in parallel).
6. Builds and validates the dependency graph.
7. Updates the `.code-workspace` file (if it exists).

Both `rwm init` and `rwm bootstrap` are idempotent.

### The bootstrap rake task

Every scaffolded package includes an empty `bootstrap` task. This is where package-specific setup belongs:

```ruby
# libs/auth/Rakefile
task :bootstrap do
  sh "bin/rails db:setup" if File.exist?("bin/rails")
  sh "cp config/credentials.example.yml config/credentials.yml" unless File.exist?("config/credentials.yml")
end
```

Common uses: database setup, copying example config files, generating local certificates, compiling native extensions.

The key property: `rwm bootstrap` runs every package's bootstrap task automatically. Developers don't need to know which packages have special setup — they run one command and everything is handled.

### After cloning

```sh
git clone <repo>
cd <repo>
rwm bootstrap
```

Every package is installed, the graph is built, hooks are active, and the workspace is ready.

### Daily workflow

```sh
git pull --rebase
rwm bootstrap          # picks up any new packages or dependency changes
git checkout -b my-feature
# ... make changes ...
rwm spec               # run all specs
rwm spec --affected    # or just the affected ones
```

The pre-push hook runs `rwm check` automatically. The post-commit hook rebuilds the graph when Gemfiles change.

## Git hooks

RWM installs two hooks during `rwm bootstrap`:

- **pre-push** — Runs `rwm check` to validate conventions before pushing. Blocks the push on failure.
- **post-commit** — Runs `rwm graph` if any Gemfile was changed in the commit. Keeps the cached graph in sync.

### Overcommit integration

If `.overcommit.yml` exists, RWM integrates with [Overcommit](https://github.com/sds/overcommit) — it merges hook configuration into the YAML file and creates executable hook scripts. Without Overcommit, RWM writes directly to `.git/hooks/`, appending to existing hooks rather than overwriting.

## Convention enforcement

```sh
rwm check
```

Three rules:

1. **No library depending on an application.** Libraries are shared building blocks and must not be coupled to deployment targets.
2. **No application depending on another application.** Applications are independent deployment units. Shared code should be extracted into a library.
3. **No circular dependencies.** Cycles make build ordering impossible and indicate tangled responsibilities.

Exits 0 on pass, 1 on violation. The pre-push hook runs this automatically.

## Rails and Zeitwerk

### How workspace libs work in Rails

Workspace libs declared via `rwm_lib` are path gems. The standard Rails boot sequence handles them automatically:

1. `config/boot.rb` calls `Bundler.setup` — adds all gem `lib/` directories to `$LOAD_PATH`
2. `config/application.rb` calls `Bundler.require(*Rails.groups)` — auto-requires every gem, including workspace libs and their transitive deps
3. `config/environment.rb` calls `Rails.application.initialize!` — Zeitwerk activates for the app's own code

By the time Zeitwerk starts in step 3, workspace libs are already loaded as plain Ruby modules. Zeitwerk never touches them — it only manages directories in `config.autoload_paths`.

**No special setup is needed in `application.rb`.** A standard Rails template works:

```ruby
# apps/web/Gemfile
require "rwm/gemfile"

source "https://rubygems.org"
gemspec

rwm_lib "auth"    # transitive deps resolved automatically
```

```ruby
# apps/web/config/application.rb
require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    config.load_defaults 8.0
  end
end
```

That's it. `Bundler.require` loads `auth` and all of its transitive workspace dependencies. No manual `Rwm.require_libs`, no ordering tricks.

### A note on Zeitwerk

> [!IMPORTANT]
> **Correction (v0.6.2):** Documentation in v0.6.1 and earlier incorrectly stated that Zeitwerk overrides `Kernel#require`. This was wrong. Zeitwerk uses `Module#autoload` and `const_missing` to lazily load files from `config.autoload_paths`. A plain `require "auth"` (from `Bundler.require` or anywhere else) works normally at any point during the boot sequence — Zeitwerk does not intercept it.

### The practical lib workflow

**Develop inside your Rails app first.** While a feature is in active development, keep the code in your Rails app's `app/` directory where Zeitwerk gives you hot reloading for free. Change a file, refresh the page, see the result.

**Extract when stable.** When the code has solidified — the interface is settled, multiple apps could use it, you're not changing it every day — extract it into a workspace lib. This is the natural monorepo rhythm: apps are where you experiment, libs are where you consolidate.

At extraction time, choose how the lib is structured.

### Traditional structure (the default)

This is what `rwm new lib` scaffolds. The lib's entry point loads all sub-files eagerly with `require_relative`:

```ruby
# libs/auth/lib/auth.rb
require_relative "auth/token"
require_relative "auth/user"

module Auth
  VERSION = "0.1.0"
end
```

**Pros:** Works everywhere — Rails, non-Rails, any Ruby app. Simple. Standard gem structure.

**Cons:** No hot reloading in Rails development. After changing a lib file, you restart the server. This is fine for stable extracted code — you're not changing it often.

This is the right choice for most workspace libs.

### Zeitwerk-compatible structure (opt-in)

Choose this when you're still actively iterating on a lib **and** multiple Rails apps consume it. The lib follows Zeitwerk naming conventions — one constant per file, no `require_relative`:

```ruby
# libs/auth/lib/auth.rb
module Auth
end

# libs/auth/lib/auth/token.rb — defines Auth::Token
# libs/auth/lib/auth/user.rb  — defines Auth::User
# Zeitwerk auto-discovers these. No require lines needed.
```

Each consuming Rails app opts in by adding the lib to its autoload paths and telling Bundler not to auto-require it:

```ruby
# apps/web/Gemfile
rwm_lib "auth", require: false    # Bundler won't auto-require
```

```ruby
# apps/web/config/application.rb
module Web
  class Application < Rails::Application
    config.autoload_paths << Rwm.lib_path("auth")
    config.eager_load_paths << Rwm.lib_path("auth")
  end
end
```

Now Zeitwerk manages `auth` — lazy loading in development (with hot reloading), eager loading in production. Changes to lib files are picked up on the next request without restarting the server.

**Trade-offs:**

- All consumer apps must add the lib to their autoload paths — this is a per-app decision
- The lib cannot use `require_relative` for its own files (Zeitwerk must control loading)
- Non-Rails consumers need a different loading strategy (e.g., `Zeitwerk::Loader.for_gem` or a `Dir.glob` require)

### What doesn't work

**Mixing `Bundler.require` and `autoload_paths` for the same lib.** If `Bundler.require` loads a lib (the default) and you also add it to `config.autoload_paths`, the lib's constants are loaded twice — once eagerly by Bundler, once lazily by Zeitwerk. Reloading breaks because Zeitwerk didn't control the initial load. Pick one or the other per lib.

**Using `require_relative` inside a Zeitwerk-managed lib.** Initial loading works fine — Zeitwerk tolerates other loading mechanisms. But after a Zeitwerk reload cycle (in development), files loaded by `require_relative` are still in `$LOADED_FEATURES`. Ruby's `require_relative` sees them as already loaded and skips them. The constants were removed by Zeitwerk's reload but never re-defined. Result: `NameError`.

### `Rwm.require_libs` — when you need it

For standard Rails apps, `Bundler.require` handles everything. `Rwm.require_libs` exists for edge cases:

- Non-standard Rails setups that don't call `Bundler.require`
- Non-Rails apps that want to load all workspace libs in one call
- Explicit control over when workspace libs are loaded

```ruby
require "rwm/rails"
Rwm.require_libs    # requires all libs resolved by rwm_lib, idempotent
```

Non-Rails apps don't need any of this — `require` workspace libs from your Gemfile anywhere in your code, as with any gem.

## VSCode integration

```sh
rwm init --vscode
```

Generates a `.code-workspace` file that configures VSCode's multi-root workspace feature. Each package becomes a separate root folder in the sidebar. After initial creation, `rwm bootstrap` and `rwm new` keep the folder list updated automatically. Existing `settings`, `extensions`, `launch`, and `tasks` keys are preserved.

## Shell completions

RWM ships with completion scripts for Bash and Zsh that provide command, flag, and package name completion.

### Bash

Add to `.bashrc` or `.bash_profile`:

```bash
source "$(gem contents ruby_workspace_manager | grep rwm.bash)"
```

### Zsh

Add to `.zshrc` (before `compinit`):

```zsh
fpath=($(gem contents ruby_workspace_manager | grep completions/rwm.zsh | xargs dirname) $fpath)
autoload -Uz compinit && compinit
```

Both scripts dynamically discover package names by scanning `libs/` and `apps/`, so tab completion always reflects your current workspace.

## Command reference

| Command | Description |
|---------|-------------|
| `rwm init [--vscode]` | Initialize a workspace. Creates dirs, Gemfile, Rakefile, .gitignore. Runs bootstrap. Idempotent. |
| `rwm bootstrap` | Install deps, build graph, install hooks, run bootstrap tasks. Idempotent. |
| `rwm new <app\|lib> <name> [--test=FW]` | Scaffold a new package. `--test`: `rspec` (default), `minitest`, `none`. |
| `rwm info <name>` | Show package details: type, path, deps, dependents. |
| `rwm graph [--dot\|--mermaid]` | Rebuild dependency graph. Optionally output DOT or Mermaid. |
| `rwm check` | Validate conventions. Exit 0 on pass, 1 on failure. |
| `rwm list` | List all packages. |
| `rwm run <task> [pkg]` | Run a Rake task across packages. |
| `rwm <task> [pkg]` | Task shortcut: `rwm spec` = `rwm run spec`. |
| `rwm affected [--committed] [--base REF]` | Show affected packages. |
| `rwm cache clean [pkg]` | Clear cached task results. |
| `rwm help` | Show available commands. |
| `rwm version` | Show version. |

### `rwm run` flags

| Flag | Description |
|------|-------------|
| `--affected` | Only run on packages affected by current changes. |
| `--committed` | With `--affected`, only consider committed changes. |
| `--base REF` | With `--affected`, compare against REF instead of auto-detected base. |
| `--dry-run` | Show what would run without executing. |
| `--no-cache` | Bypass task caching. Force all tasks to run. |
| `--buffered` | Buffer output per-package and print on completion. |
| `--concurrency N` | Limit parallel workers. Default: number of CPU cores. |

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
