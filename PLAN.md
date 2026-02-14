# RWM (Ruby Workspace Manager) — Implementation Plan

## Context

Build an Nx-like monorepo tool for Ruby called **rwm**. Convention-over-configuration, zero runtime deps (Ruby stdlib + Bundler only), delegates to Rake for task execution. Distributed as a gem.

## Monorepo Convention

```
my-project/
├── libs/           # shared libraries (can depend on other libs)
│   ├── auth/       # each has Gemfile, gemspec, Rakefile
│   └── billing/
├── apps/           # applications (can depend on libs only)
│   ├── api/
│   └── web/
└── .rwm/           # rwm state directory (workspace root marker)
    └── graph.json  # auto-generated dependency graph
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
│       ├── gemfile_parser.rb     # Bundler DSL → path deps
│       ├── dependency_graph.rb   # DAG via TSort (cycle detection, topo sort)
│       ├── convention_checker.rb # structural rule enforcement
│       ├── affected_detector.rb  # git diff → affected packages
│       ├── task_runner.rb        # sequential + parallel rake execution
│       ├── overcommit.rb         # overcommit setup + rwm-specific hooks
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
| `rwm init` | Create `libs/`, `apps/`, `.rwm/`, then run `bootstrap` automatically. Idempotent — safe to re-run to fix a broken state |
| `rwm bootstrap` | Full developer onboarding: install all gems, run bootstrap tasks, build graph, set up overcommit |
| `rwm new app <name>` | Scaffold a new app in `apps/<name>/` with Gemfile, gemspec, Rakefile, lib/ |
| `rwm new lib <name>` | Scaffold a new lib in `libs/<name>/` with Gemfile, gemspec, Rakefile, lib/ |
| `rwm info <name>` | Show details about a package: type, path, deps, dependents, rake tasks |
| `rwm graph` | Parse all Gemfiles, build DAG, validate, write `.rwm/graph.json` |
| `rwm check` | Validate graph (cycles, conventions, staleness). Exit 0/1/2 |
| `rwm test` | Run `rake test` in all packages (topo order). Shortcut for `rwm run test` |
| `rwm run <task> --affected` | Only run on packages changed since base branch + their dependents |
| `rwm list` | Print table of packages (name, type, path, deps) |
| `rwm affected` | Show which packages are affected by current changes |

## Key Design Decisions

1. **Dependency detection**: Parse Gemfiles for `path:` deps using `Bundler::Dsl`. No source scanning — Bundler already enforces load paths.
2. **Graph**: Ruby's `TSort` stdlib (Tarjan's algorithm) for topological sort + cycle detection. Stored as JSON in `.rwm/graph.json`.
3. **Task execution**: `bundle exec rake <task>` in each package dir. Always parallel — groups packages by execution level (packages at same level have no interdependency), runs each level concurrently.
4. **Affected detection**: `git diff --name-only` → map files to packages → walk graph for transitive dependents. Root-level changes = all packages affected.
5. **Overcommit for git hooks**: Use the [overcommit](https://github.com/sds/overcommit) gem instead of hand-rolled git hooks. `rwm init` installs overcommit and configures rwm-specific hooks (e.g. `pre-push` runs `rwm check`, `post-commit` rebuilds graph on Gemfile changes). Users are expected to use overcommit — rwm leans into it.
6. **No CLI framework**: Plain `OptionParser` from stdlib. No Thor, no GLI.
7. **Zero runtime deps**: Only Ruby stdlib + Bundler (ships with Ruby since 2.6). Overcommit is the sole exception — it's a development dependency that rwm sets up for users.
8. **No config file**: The `.rwm/` directory is the workspace root marker and contains all rwm state. No `.rwm.yml`. Sensible defaults are baked in (base branch = `main`, package dirs = `libs/` + `apps/`). If configuration becomes necessary later, it lives inside `.rwm/`.
9. **Package scaffolding**: `rwm new app/lib <name>` generates a standard Ruby package structure so every package is consistent. Includes Gemfile, gemspec, Rakefile, `lib/<name>.rb`, and a basic spec setup.
10. **Bootstrap as onboarding**: `rwm bootstrap` is the single command a developer runs after cloning. It handles everything: `bundle install` in every package (topological order so deps are available first), runs `rake bootstrap` where available, builds the dependency graph, validates conventions, and sets up overcommit. Idempotent — safe to run again.

## Core Components

### Workspace (`lib/rwm/workspace.rb`)
- Walks up from cwd to find `.rwm/` directory (the workspace root marker)
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

### ConventionChecker (`lib/rwm/convention_checker.rb`)
- Checks: no app→app deps, no lib→app deps, no cycles
- Raises `ConventionError` with all violations listed

### AffectedDetector (`lib/rwm/affected_detector.rb`)
- Runs `git diff --name-only` against base branch (default: `main`)
- Maps changed files to packages by path prefix
- Walks graph to find transitive dependents of changed packages

### TaskRunner (`lib/rwm/task_runner.rb`)
- Always runs in parallel: groups packages by execution level, runs each level concurrently (Thread-based)
- Packages at the same level have no interdependencies, so they're safe to run simultaneously
- Skips downstream levels on failure
- Streams output with `[package_name]` prefixes

### Bootstrap (`lib/rwm/commands/bootstrap.rb`)
- The "clone and go" command — everything a developer needs after `git clone`
- Steps executed in order:
  1. `bundle install` in each package (parallel by execution level — libs before apps that depend on them)
  2. `rake bootstrap` in each package that defines the task (parallel by execution level)
  3. Build and validate the dependency graph (`rwm graph` + `rwm check`)
  4. Set up overcommit (install gem, install hooks, write config)
- Streams progress with clear status output per package
- Fails fast with a helpful message if any step fails
- Idempotent — safe to re-run

### Init (`lib/rwm/commands/init.rb`)
- Creates the workspace structure (`libs/`, `apps/`, `.rwm/`) if not already present
- Then calls `bootstrap` to do the full setup
- Idempotent — if `.rwm/` was deleted or things are broken, just run `rwm init` again to recover

### Overcommit (`lib/rwm/overcommit.rb`)
- Sets up overcommit in the workspace: installs gem, runs `overcommit --install`, writes `.overcommit.yml`
- Configures rwm-specific hooks:
  - `pre_push`: runs `rwm check`, blocks push on failure
  - `post_commit`: runs `rwm graph` if any Gemfile changed in the commit
- Called by `bootstrap`

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
2. Workspace — root discovery (walks up to find `.rwm/`) + package scanning
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

## Verification

1. `bundle exec rspec` — all unit specs pass
2. Create a test monorepo with 2 libs + 1 app, verify full workflow
3. Verify overcommit hooks fire correctly on commit/push

## Future Considerations (Not in v1)

- Computation caching (content hash-based, like Nx)
- Remote caching (shared across CI + devs)
- Custom composite tasks (config inside `.rwm/` if needed)
- Watch mode
- Graphviz output (`rwm graph --dot`)
