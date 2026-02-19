# Code Review — Areas of Improvement

## High Priority

### 1. Worker thread exceptions cause deadlock

**File:** `lib/rwm/task_runner.rb`

If `Open3.capture3` raises an unexpected exception (e.g., `Errno::ENOENT` if `bundle` isn't found in a package dir), the thread dies without calling `condition.broadcast`. The main loop hangs forever waiting on the condition variable. The thread body needs a `begin/rescue/ensure` that always removes itself from `running` and broadcasts.

### 2. `Commands::Run` summary miscounts skipped packages

**File:** `lib/rwm/commands/run.rb:101-109`

When a package fails and its dependents are skipped, those dependents are reported as "failed" in the summary — not "skipped." The `skipped` variable from the partition is unused, and `skipped_from_rest` only catches task-not-found skips, not dependency-failure skips (which have `skipped: nil`).

## Medium Priority

### 3. ~~CLI only catches `Rwm::Error`~~ ✅ Fixed

**File:** `lib/rwm/cli.rb`

Added `rescue Interrupt` (exit 130) and `rescue StandardError` catch-all (friendly message, backtrace in verbose mode).

### 4. ~~`NO_TASK_PATTERN` relies on exact Rake error text~~ ✅ Fixed

**File:** `lib/rwm/task_runner.rb`

Replaced with case-insensitive multi-pattern regex matching both "don't know how to build task" variants and "rake --tasks" hint text.

### 5. ~~Root-level file changes mark ALL packages affected~~ ✅ Fixed

**File:** `lib/rwm/affected_detector.rb`

Inert root files (*.md, LICENSE*, .github/**, docs/**, etc.) are now ignored via `IGNORED_ROOT_PATTERNS`. Custom patterns supported via `.rwm/affected_ignore`.

### 6. ~~`Rwm.resolved_libs` is global mutable state~~ ✅ Fixed

**File:** `lib/rwm/gemfile.rb`

Sandbox DSL instances used by `scan_transitive_deps` are now flagged with `@rwm_scanning`, preventing them from polluting `Rwm.resolved_libs`.

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
