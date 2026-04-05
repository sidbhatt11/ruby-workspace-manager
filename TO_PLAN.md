# To Plan

Items to investigate and plan before implementing.

## 1. Railtie for automatic Zeitwerk integration

**What a Railtie could still provide: automatic `config.autoload_paths` for Zeitwerk dev reloading.**

Currently, if a user wants Zeitwerk to manage a workspace lib (for hot reloading in development), they must manually configure it per lib in their Rails app:

```ruby
# apps/web/Gemfile
rwm_lib "auth", require: false

# apps/web/config/application.rb
config.autoload_paths << Rwm.lib_path("auth")
config.eager_load_paths << Rwm.lib_path("auth")
```

A Railtie could automate this: detect which workspace libs have `require: false` and add their paths to the autoloader automatically.

**What to investigate:**
- Can the Railtie read Bundler's dependency metadata to find which workspace libs have `require: false`?
- Should this be driven by Gemfile options (`rwm_lib "auth", require: false`) or by a separate config (`config.rwm.zeitwerk_libs = %w[auth]`)?
- The lib must follow Zeitwerk conventions (no `require_relative` for sub-files). How do we validate or warn about this?
- `require: false` applies globally — a non-Rails consumer of the same lib would need to handle loading differently. Is this acceptable?
- Should `rwm new lib` gain a `--zeitwerk` flag that scaffolds the lib in Zeitwerk-compatible style (no `require_relative`)?

**Constraints discovered during v0.6.2 investigation:**
- A lib cannot be both loaded by `Bundler.require` AND in `config.autoload_paths` — double-load conflict
- Files loaded by `require_relative` survive in `$LOADED_FEATURES` across Zeitwerk reload cycles, causing `NameError` after reload — libs in autoload_paths must not use `require_relative`
- Multiple Zeitwerk loaders coexist fine (Rails' + gems'), but each must manage a distinct file tree

**Goal:** A Railtie that automatically adds Zeitwerk-opted workspace libs to `config.autoload_paths`, so the user only needs `rwm_lib "auth", require: false` in the Gemfile and nothing in `application.rb`.

## 2. `rwm exec` — run arbitrary commands across packages

`rwm run` only runs Rake tasks. But a lot of ad-hoc monorepo work is just "run this command in every package" — `bundle outdated`, `ruby -v`, `wc -l lib/**/*.rb`, etc. Having to define a Rake task for each one-off command is friction.

**What to investigate:**
- Command design: `rwm exec "bundle outdated"` or `rwm exec -- bundle outdated`? The `--` separator is more conventional for passing through arguments
- Should it support all the same flags as `rwm run` (`--affected`, `--concurrency`, `--buffered`)?
- Should it respect the dependency graph for ordering, or just run in parallel with no ordering? Probably no ordering needed since these are typically read-only/informational
- Error handling: fail-fast vs. continue-on-error? Probably continue and summarize at the end
- Caching: almost certainly no — exec commands are ad-hoc by nature

**Goal:** `rwm exec -- bundle outdated` runs the command in every package directory, with output prefixed by package name. Supports `--affected` and `--concurrency` for filtering and parallelism.

## 3. Dependency version consistency checking

A common monorepo pain point is version drift — one package pins `pg ~> 1.4` while another uses `pg ~> 1.5`. This silently bites you when packages are deployed together but were developed against different dependency versions. `rwm check` currently validates graph structure but doesn't look at gem versions.

**What to investigate:**
- Parse all package Gemfiles and Gemfile.locks for external gem versions
- Define what "inconsistent" means: different version constraints for the same gem? Or different resolved versions in lockfiles?
- Should this be part of `rwm check` (fail CI) or a separate `rwm audit` / `rwm versions` command (informational)?
- How to handle intentional version differences (e.g., a package migrating to a newer version)?
- Should there be an allowlist/ignorelist for known acceptable drift?

**Goal:** Surface version inconsistencies across packages so teams can catch drift early. Likely a new flag on `rwm check` (e.g., `rwm check --versions`) so it integrates with the existing pre-push hook.

## 4. Watch mode

`rwm watch spec` — re-run affected specs when files change. Ruby culture is deeply TDD-oriented, and the feedback loop of "save file → affected specs re-run instantly" is the workflow developers expect from tools like Guard.

**What to investigate:**
- File watching: use `rb-fsevent` (macOS), `rb-inotify` (Linux), or `listen` gem? All are external deps, which conflicts with the zero-dependency philosophy. Alternatively, poll with `stat` on a short interval
- Scope: watch the entire workspace and map changed files to affected packages (reuse `AffectedDetector` logic), then re-run only those
- Debouncing: batch rapid file changes (e.g., save + auto-format) into a single run
- Output: clear screen between runs? Show a summary of what changed and what's re-running?
- Could this be implemented as a thin wrapper that shells out to `fswatch` or `watchman` if available, avoiding a Ruby dependency?

**Goal:** `rwm watch spec` provides a fast TDD feedback loop — change a file in `auth`, specs for `auth` and its dependents re-run automatically.

## 5. `rwm why <package>`

When `rwm affected` flags a package you didn't expect, there's no way to understand why without mentally tracing the dependency graph. This is especially confusing in large workspaces with deep transitive chains.

**What to investigate:**
- Two use cases: "why is X affected?" (trace from changed files → package → dependents) and "why does X depend on Y?" (shortest path in the dependency graph)
- Output format: a chain like `auth (changed) → billing (depends on auth) → api (depends on billing)`
- Should it integrate with `rwm affected --why` or be a standalone `rwm why` command?
- For dependency chains: use BFS on the graph to find the shortest path between two packages

**Goal:** `rwm why billing` explains "billing is affected because auth changed, and billing depends on auth." `rwm why api auth` shows the dependency path from api to auth.

## 6. Selective bootstrap

`rwm bootstrap` installs and sets up every package in the workspace. After adding a single dependency to one package, you shouldn't have to wait for the entire workspace to re-bootstrap.

**What to investigate:**
- `rwm bootstrap auth billing` — only run `bundle install` and `rake bootstrap` for the named packages (and their dependencies, transitively?)
- Should it also install transitive dependents? If you bootstrap `auth` and `billing` depends on `auth`, should `billing` get a `bundle install` too?
- How does this interact with the root-level bootstrap steps (root `bundle install`, hook installation, graph rebuild)?
- Maybe: root steps always run, package steps are filtered. Or add a `--skip-root` flag

**Goal:** `rwm bootstrap auth` installs deps and runs bootstrap for `auth` (and its dependencies) without touching unrelated packages. Root-level steps still run.
