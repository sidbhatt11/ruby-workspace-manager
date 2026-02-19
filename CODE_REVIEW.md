# Code Review — Areas of Improvement

## High Priority

### 1. Worker thread exceptions cause deadlock

**File:** `lib/rwm/task_runner.rb`

If `Open3.capture3` raises an unexpected exception (e.g., `Errno::ENOENT` if `bundle` isn't found in a package dir), the thread dies without calling `condition.broadcast`. The main loop hangs forever waiting on the condition variable. The thread body needs a `begin/rescue/ensure` that always removes itself from `running` and broadcasts.

### 2. `Commands::Run` summary miscounts skipped packages

**File:** `lib/rwm/commands/run.rb:101-109`

When a package fails and its dependents are skipped, those dependents are reported as "failed" in the summary — not "skipped." The `skipped` variable from the partition is unused, and `skipped_from_rest` only catches task-not-found skips, not dependency-failure skips (which have `skipped: nil`).

## Medium Priority

### 3. CLI only catches `Rwm::Error`

**File:** `lib/rwm/cli.rb:54-57`

A malformed Gemfile raises `Bundler::GemfileError`, a permission issue raises `Errno::EACCES` — both result in raw backtraces. A broader rescue with a friendly message for common non-Rwm exceptions would improve UX.

### 4. `NO_TASK_PATTERN` relies on exact Rake error text

**File:** `lib/rwm/task_runner.rb:10`

`/Don't know how to build task/` is fragile — a future Rake version or different locale could break this. Rake does exit with a specific status code for missing tasks, which might be a more robust signal.

### 5. Root-level file changes mark ALL packages affected

**File:** `lib/rwm/affected_detector.rb:22-25`

Editing `README.md`, `.github/ci.yml`, or any root file triggers a full run across every package. An exclusion pattern config (or ignoring known-inert paths like `docs/`, `.github/`) would save a lot of unnecessary CI work.

### 6. `Rwm.resolved_libs` is global mutable state

**File:** `lib/rwm/gemfile.rb:19`

`GemfileParser.parse` evaluates Gemfiles which trigger `rwm_lib`, populating `resolved_libs` as a side effect. If graph building and `Rwm.require_libs` run in the same process, libs from other packages' Gemfiles leak in.

## Low Priority / Performance

### 7. Cache declarations shell out serially for every package

**File:** `lib/rwm/task_cache.rb:102-114`

Each package spawns `bundle exec rake rwm:cache_config` — a full Ruby boot. With 20 packages, that's 20 cold process starts before parallel execution even begins. Could be parallelized or batched.

### 8. `execution_levels` is O(n^3)

**File:** `lib/rwm/dependency_graph.rb:69-89`

`levels.flatten` rebuilds an array each iteration, then `placed.include?` does linear search. Using a `Set` built incrementally would bring it to O(n*m) where m is edge count. Fine for <100 packages, but worth noting.

### 9. Init command uses `Dir.pwd` not git root

**File:** `lib/rwm/commands/init.rb:33`

Running `rwm init` from a subdirectory initializes in the wrong place. Other commands use `Workspace.find` which walks up to the git root.

### 10. No file locking on `.rwm/graph.json`

Two concurrent `rwm` processes could corrupt the cached dependency graph.

## What's Good

- **No command injection anywhere** — consistently uses array-form `system()`/`Open3.capture3`, never interpolates into shell strings
- **Name validation** prevents path traversal in `rwm new`
- **Test infrastructure** with real temp monorepos is solid
- **The DAG scheduler design** is clean (minus the exception handling gap)
