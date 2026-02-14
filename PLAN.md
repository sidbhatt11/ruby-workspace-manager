# RWM (Ruby Workspace Manager) — Implementation Plan

## Context

Build an Nx-like monorepo tool for Ruby called **rwm**. Convention-over-configuration, zero runtime deps (Ruby stdlib + Bundler only), delegates to Rake for task execution. Distributed as a gem.

## Monorepo Convention

```
my-project/              # git root = workspace root
├── libs/                # shared libraries (can depend on other libs)
│   ├── auth/            # each has Gemfile, gemspec, Rakefile
│   └── billing/
├── apps/                # applications (can depend on libs only)
│   ├── api/
│   └── web/
└── .rwm/                # generated state (gitignored)
    └── graph.json       # auto-generated dependency graph
```

**Rules:** libs cannot import apps. Apps cannot import other apps. No cycles.

## Gem Structure

```
rwm/
├── bin/rwm
├── lib/
│   ├── rwm.rb                    # root autoloads, version
│   └── rwm/
│       ├── version.rb
│       ├── errors.rb             # CycleError, ConventionError, etc.
│       ├── cli.rb                # OptionParser-based dispatcher
│       ├── workspace.rb          # discovers root, packages
│       ├── package.rb            # single lib/app model
│       ├── gemfile.rb            # Bundler DSL extension (rwm_lib)
│       ├── gemfile_parser.rb     # Bundler DSL → path deps
│       ├── dependency_graph.rb   # DAG via TSort (cycle detection, topo sort)
│       ├── convention_checker.rb # structural rule enforcement
│       ├── affected_detector.rb  # git diff → affected packages
│       ├── task_runner.rb        # sequential + parallel rake execution
│       ├── task_cache.rb         # redo-style content-hash caching
│       ├── rake.rb               # Rake DSL extension (cacheable_task)
│       ├── git_hooks.rb          # plain git hook installation
│       ├── overcommit.rb         # overcommit setup (when .overcommit.yml exists)
│       └── commands/
│           ├── init.rb           # rwm init
│           ├── bootstrap.rb     # rwm bootstrap
│           ├── new.rb            # rwm new app/lib <name>
│           ├── info.rb           # rwm info <name>
│           ├── graph.rb          # rwm graph
│           ├── check.rb          # rwm check
│           ├── run.rb            # rwm test/build/any-rake-task
│           ├── list.rb           # rwm list
│           └── affected.rb       # rwm affected
├── spec/
│   └── rwm/                     # unit + integration specs
├── rwm.gemspec
├── Gemfile
└── Rakefile
```

## CLI Commands

| Command | Behavior |
|---------|----------|
| `rwm init` | Create dirs, Gemfile, Rakefile, update `.gitignore`, then call `bootstrap`. Pass `--vscode` to generate `.code-workspace`. Idempotent — safe to re-run |
| `rwm bootstrap` | `bundle install` + `rake bootstrap` in root, then same in all packages, then build graph. The "clone and go" command |
| `rwm new app <name>` | Scaffold a new app in `apps/<name>/` with Gemfile, gemspec, Rakefile, lib/ |
| `rwm new lib <name>` | Scaffold a new lib in `libs/<name>/` with Gemfile, gemspec, Rakefile, lib/ |
| `rwm info <name>` | Show details about a package: type, path, deps, dependents, rake tasks |
| `rwm graph` | Parse all Gemfiles, build DAG, validate, write `.rwm/graph.json`. `--dot` / `--mermaid` for visualization |
| `rwm check` | Validate graph (cycles, conventions, staleness). Exit 0/1/2 |
| `rwm test` | Run `rake test` in all packages (topo order). Shortcut for `rwm run test` |
| `rwm run <task> --affected` | Only run on packages changed since base branch + their dependents |
| `rwm run <task> --no-cache` | Bypass automatic task-level caching |
| `rwm list` | Print table of packages (name, type, path, deps) |
| `rwm affected` | Show which packages are affected by current changes |

## Key Design Decisions

1. **Dependency detection**: Parse Gemfiles for `path:` deps using `Bundler::Dsl`. No source scanning — Bundler already enforces load paths.
2. **Graph**: Ruby's `TSort` stdlib (Tarjan's algorithm) for topological sort + cycle detection. Stored as JSON in `.rwm/graph.json`.
3. **Task execution**: `bundle exec rake <task>` in each package dir. Always parallel — groups packages by execution level (packages at same level have no interdependency), runs each level concurrently.
4. **Affected detection**: `git diff --name-only` → map files to packages → walk graph for transitive dependents. Root-level changes = all packages affected.
5. **Git hooks**: Bootstrap always installs git hooks (`pre-push` runs `rwm check`, `post-commit` rebuilds graph on Gemfile changes). If `.overcommit.yml` exists, hooks are managed via overcommit. Otherwise, plain git hooks are written to `.git/hooks/`.
6. **No CLI framework**: Plain `OptionParser` from stdlib. No Thor, no GLI.
7. **Zero runtime deps**: Only Ruby stdlib + Bundler (ships with Ruby since 2.6). Overcommit is the sole exception — it's a development dependency that rwm sets up for users.
8. **No config file**: The git root is the workspace root. `.rwm/` is generated state (gitignored), created on demand to store `graph.json`. Sensible defaults are baked in (base branch = auto-detected from git, package dirs = `libs/` + `apps/`). If configuration becomes necessary later, it lives inside `.rwm/`.
11. **Auto-detect base branch**: Instead of hardcoding `main`, use `git symbolic-ref refs/remotes/origin/HEAD` to detect the remote's default branch. Falls back to `main`, then `master`. No config needed — works with any branching convention.
12. **Task caching (task-level, redo-style)**: Inspired by DJB's redo. Tasks declared with `cacheable_task` in Rakefiles are automatically cached. For each (package, task) pair, compute a content hash of the package's source files + the hashes of its dependencies. If the hash matches a previous successful run, skip the task entirely. If outputs are declared, they must exist for the cache to be valid. Cache is local (`.rwm/cache/`), ephemeral, gitignored. Bypass with `--no-cache`.
9. **Package scaffolding**: `rwm new app/lib <name>` generates a standard Ruby package structure so every package is consistent. Includes Gemfile, gemspec, Rakefile (with an empty `bootstrap` task as a hint), `lib/<name>.rb`, and a basic spec setup.
10. **Bootstrap as onboarding**: `rwm bootstrap` is the single command a developer runs after cloning. It handles everything: `bundle install` in every package (topological order so deps are available first), runs `rake bootstrap` where available, builds the dependency graph, validates conventions, and sets up overcommit. Idempotent — safe to run again.

## Core Components

### Workspace (`lib/rwm/workspace.rb`)
- Uses `git rev-parse --show-toplevel` to find the workspace root (git root = workspace root)
- Discovers packages by scanning `libs/` and `apps/` for directories containing a `Gemfile`

### Package (`lib/rwm/package.rb`)
- Model for a single lib or app
- Knows its name, path, type (:lib/:app), and whether it has a Rakefile
- Can check if a specific rake task exists

### GemfileParser (`lib/rwm/gemfile_parser.rb`)
- Uses `Bundler::Dsl` to parse a Gemfile
- Extracts only `path:` dependencies
- Resolves relative paths to absolute, then matches against known packages

### DependencyGraph (`lib/rwm/dependency_graph.rb`)
- Includes Ruby's `TSort` module
- Maintains adjacency list (deps) and reverse adjacency list (dependents)
- Provides: `topological_order`, `detect_cycles`, `transitive_dependents`, `execution_levels`
- Serializes to/from JSON for `.rwm/graph.json`
- `DependencyGraph.load(workspace)`: reads edges from cached `.rwm/graph.json` and populates packages from the workspace. Falls back to `build` if the cache doesn't exist. Used by most commands (run, list, check, affected, info) to avoid re-parsing every Gemfile.
- `DependencyGraph.build(workspace)`: full rebuild by parsing all Gemfiles. Used by `graph` and `bootstrap`.

### ConventionChecker (`lib/rwm/convention_checker.rb`)
- Checks: no app→app deps, no lib→app deps, no cycles
- Raises `ConventionError` with all violations listed

### AffectedDetector (`lib/rwm/affected_detector.rb`)
- Auto-detects the base branch via `git symbolic-ref refs/remotes/origin/HEAD` (falls back to `main` then `master`)
- Runs `git diff --name-only` against the detected base branch
- Maps changed files to packages by path prefix
- Walks graph to find transitive dependents of changed packages

### TaskRunner (`lib/rwm/task_runner.rb`)
- Always runs in parallel: groups packages by execution level, runs each level concurrently (Thread-based)
- Packages at the same level have no interdependencies, so they're safe to run simultaneously
- Skips downstream levels on failure
- Streams output with `[package_name]` prefixes

### Init (`lib/rwm/commands/init.rb`)
- Creates `libs/` and `apps/` directories if not already present
- Creates a root `Gemfile` if missing (includes `rwm` gem)
- Creates a root `Rakefile` if missing (includes an empty `bootstrap` task that prints a helpful message)
- Adds `.rwm/` to `.gitignore` (appends if file exists, creates if not; skips if already present)
- `--vscode` flag generates a `.code-workspace` file
- Calls `bootstrap` as the last step
- Idempotent — safe to re-run anytime to fix a broken state

### Bootstrap (`lib/rwm/commands/bootstrap.rb`)
- Follows the same pattern everywhere: `bundle install` → `rake bootstrap` (if available)
- Steps:
  1. Bootstrap the root: `bundle install`, then `rake bootstrap` if defined (init ensures it is)
  2. Install git hooks (overcommit if `.overcommit.yml` exists, plain git hooks otherwise)
  3. Build the dependency graph once (used for execution ordering in subsequent steps)
  4. Bootstrap all packages: same pattern in each package (parallel by execution level)
  5. Save the graph to `.rwm/graph.json` and validate conventions
  6. Update `.code-workspace` (only if the file already exists)
- Root Rakefile has a `bootstrap` task by default (prints a helpful message, developers customize it for binstubs, shared tooling, etc.)
- Streams progress with clear status output
- Fails fast with a helpful message if any step fails
- Idempotent — safe to re-run

### GemfileDsl (`lib/rwm/gemfile.rb`)
- Bundler DSL extension via `prepend` on `Bundler::Dsl`
- `rwm_lib(name)`: resolves to `gem(name, path: "<root>/libs/<name>")`
- Workspace root discovered via `git rev-parse --show-toplevel`
- Loaded in Gemfiles with `require "rwm/gemfile"`

### RakeCache / cacheable_task (`lib/rwm/rake.rb`)
- Defines top-level `cacheable_task(name, output: nil, &block)` for Rakefiles
- Wraps `Rake::Task.define_task` — creates a normal rake task
- Registers cache metadata in `Rwm::RakeCache.declarations`
- Defines `rwm:cache_config` rake task that outputs declarations as JSON
- Used by TaskCache to auto-detect which tasks are cacheable

### TaskCache (`lib/rwm/task_cache.rb`)
- Redo-style content-hash caching for task results
- For each (package, task) pair, computes a cache key from:
  - SHA256 of all source files in the package (sorted, deterministic)
  - Cache keys of all dependency packages (transitive — if a dep changes, dependents invalidate)
  - The task name itself
- `cacheable?(package, task)`: discovers cacheable tasks by running `bundle exec rake rwm:cache_config` (cached per-run)
- `outputs_exist?(package, output_pattern)`: checks declared output files/globs exist
- On cache hit: skip the task, print "[cached]"
- On cache miss: run the task, store the hash on success
- Cache lives in `.rwm/cache/` — local, ephemeral, gitignored
- Auto-enabled for tasks declared with `cacheable_task` — bypass with `--no-cache`

### VscodeWorkspace (`lib/rwm/vscode_workspace.rb`)
- Generates/updates a `<dirname>.code-workspace` file for VSCode multi-root workspace support
- `folders` array: root `.` first, then libs sorted, then apps sorted (relative paths)
- Preserves existing `settings`, `extensions`, `launch`, `tasks` keys — only replaces `folders`
- Opt-in: `rwm init --vscode` creates it initially; `bootstrap` and `new` update it only if the file already exists

### GitHooks (`lib/rwm/git_hooks.rb`)
- Installs plain git hooks to `.git/hooks/`
- `pre-push`: runs `rwm check`, blocks push on failure
- `post-commit`: runs `rwm graph` if any Gemfile changed in the commit
- Appends to existing hooks without duplicating
- Used when overcommit is not present

### Overcommit (`lib/rwm/overcommit.rb`)
- Sets up overcommit in the workspace: runs `overcommit --install`, merges rwm hooks into `.overcommit.yml`
- Merges, not overwrites — preserves any existing user hooks in `.overcommit.yml`
- Configures rwm-specific hooks via overcommit's CustomScript mechanism
- Used when `.overcommit.yml` exists in the workspace root

## graph.json Format

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

## Implementation Phases

### Phase 1: Core Foundation
1. Gem skeleton (gemspec, bin/rwm, lib/rwm.rb, version.rb, errors.rb)
2. Workspace — root discovery (git root) + package scanning
3. Package — lib/app model
4. GemfileParser — Bundler DSL path dep extraction
5. DependencyGraph — TSort DAG
6. ConventionChecker — rule enforcement
7. CLI — command dispatcher
8. Commands: init, bootstrap, graph, check, list
9. Commands: new (app/lib scaffolding), info
10. Specs for all above

### Phase 2: Task Execution
11. TaskRunner — sequential + parallel
12. Commands::Run — `rwm run <task>` and shortcuts
13. Specs

### Phase 3: Affected Detection
14. AffectedDetector — git diff + graph walk
15. Commands::Affected
16. Wire `--affected` into `rwm run`
17. Specs

### Phase 4: Overcommit Integration
18. Overcommit — setup, hook configuration
19. Wire into `rwm init`
20. Specs

### Phase 5: Task Caching
21. TaskCache — content-hash based, redo-style
22. Wire caching into `rwm run`
23. Specs

### Phase 6: Gemfile DSL
24. `lib/rwm/gemfile.rb` — Bundler DSL extension (`rwm_lib`)
25. Update `rwm new` scaffold to add rwm as dev dep, include `require "rwm/gemfile"` in Gemfile
26. Specs

### Phase 7: Rakefile DSL + Task-level Caching
27. `lib/rwm/rake.rb` — `cacheable_task` DSL + `rwm:cache_config` introspection
28. Update TaskCache for task-level opt-in (`cacheable?`) + output verification (`outputs_exist?`)
29. Replace `--cache` with `--no-cache` in Commands::Run (auto-detect cacheable tasks)
30. Update `rwm new` scaffold to use `cacheable_task` in Rakefiles
31. Specs

## Verification

1. `bundle exec rspec` — all unit specs pass
2. Create a test monorepo with 2 libs + 1 app, verify full workflow
3. Verify overcommit hooks fire correctly on commit/push
4. Verify task caching skips unchanged packages and invalidates on changes

## Future Considerations (Not in v1)

- Remote caching (shared across CI + devs)
- Custom composite tasks (config inside `.rwm/` if needed)
- Watch mode
