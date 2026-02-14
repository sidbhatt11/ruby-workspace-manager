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
├── .rwm.yml        # auto-generated config
└── .rwm/graph.json # auto-generated dependency graph
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
│       ├── config.rb             # .rwm.yml loader
│       ├── workspace.rb          # discovers root, packages
│       ├── package.rb            # single lib/app model
│       ├── gemfile_parser.rb     # Bundler DSL → path deps
│       ├── dependency_graph.rb   # DAG via TSort (cycle detection, topo sort)
│       ├── convention_checker.rb # structural rule enforcement
│       ├── affected_detector.rb  # git diff → affected packages
│       ├── task_runner.rb        # sequential + parallel rake execution
│       ├── git_hooks.rb          # install/uninstall/status
│       └── commands/
│           ├── init.rb           # rwm init
│           ├── graph.rb          # rwm graph
│           ├── check.rb          # rwm check
│           ├── run.rb            # rwm test/build/any-rake-task
│           ├── list.rb           # rwm list
│           ├── affected.rb       # rwm affected
│           └── hooks.rb          # rwm hooks install/uninstall/status
├── spec/
│   └── rwm/                     # unit + integration specs
├── rwm.gemspec
├── Gemfile
└── Rakefile
```

## CLI Commands

| Command | Behavior |
|---------|----------|
| `rwm init` | Create `libs/`, `apps/`, `.rwm.yml`, `.rwm/`, install git hooks |
| `rwm graph` | Parse all Gemfiles, build DAG, validate, write `.rwm/graph.json` |
| `rwm check` | Validate graph (cycles, conventions, staleness). Exit 0/1/2 |
| `rwm test` | Run `rake test` in all packages (topo order). Shortcut for `rwm run test` |
| `rwm run <task> --affected` | Only run on packages changed since base branch + their dependents |
| `rwm list` | Print table of packages (name, type, path, deps) |
| `rwm affected` | Show which packages are affected by current changes |
| `rwm hooks install/uninstall/status` | Manage git hooks |

## Key Design Decisions

1. **Dependency detection**: Parse Gemfiles for `path:` deps using `Bundler::Dsl`. No source scanning — Bundler already enforces load paths.
2. **Graph**: Ruby's `TSort` stdlib (Tarjan's algorithm) for topological sort + cycle detection. Stored as JSON in `.rwm/graph.json`.
3. **Task execution**: `bundle exec rake <task>` in each package dir. Parallel mode groups packages by execution level (packages at same level have no interdependency).
4. **Affected detection**: `git diff --name-only` → map files to packages → walk graph for transitive dependents. Root-level changes = all packages affected.
5. **Git hooks**: Shell scripts that call `rwm` binary. `post-commit` rebuilds graph on Gemfile changes, `pre-push` runs `rwm check`.
6. **No CLI framework**: Plain `OptionParser` from stdlib. No Thor, no GLI.
7. **Zero runtime deps**: Only Ruby stdlib + Bundler (ships with Ruby since 2.6).

## Core Components

### Workspace (`lib/rwm/workspace.rb`)
- Walks up from cwd to find `.rwm.yml` (the workspace root marker)
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
- Runs `git diff --name-only` against base branch (configurable, default: `main`)
- Maps changed files to packages by path prefix
- Walks graph to find transitive dependents of changed packages

### TaskRunner (`lib/rwm/task_runner.rb`)
- Sequential mode: runs in topological order, skips downstream packages on failure
- Parallel mode: groups by execution level, runs each level concurrently (Thread-based)
- Streams output with `[package_name]` prefixes

### GitHooks (`lib/rwm/git_hooks.rb`)
- `post-commit`: rebuilds graph if any Gemfile changed in the commit
- `pre-push`: runs `rwm check`, blocks push on failure
- Handles co-existing with user's own hooks (appends, doesn't replace)

### Config (`lib/rwm/config.rb`)
- Loads `.rwm.yml` with YAML.safe_load
- Fields: `base_branch` (default: main), `max_workers` (default: auto/nproc), `package_dirs` (default: libs, apps)

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
2. Config — YAML loader
3. Workspace — root discovery + package scanning
4. Package — lib/app model
5. GemfileParser — Bundler DSL path dep extraction
6. DependencyGraph — TSort DAG
7. ConventionChecker — rule enforcement
8. CLI — command dispatcher
9. Commands: init, graph, check, list
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

### Phase 4: Git Hooks
18. GitHooks — install/uninstall/status
19. Commands::Hooks
20. Wire into `rwm init`
21. Specs

## Verification

1. `bundle exec rspec` — all unit specs pass
2. Create a test monorepo with 2 libs + 1 app, verify full workflow
3. Manually test git hooks by committing a Gemfile change

## Future Considerations (Not in v1)

- Computation caching (content hash-based, like Nx)
- Remote caching (shared across CI + devs)
- Custom composite tasks in `.rwm.yml`
- Watch mode
- Generators (`rwm generate lib my_lib`)
- Graphviz output (`rwm graph --dot`)
