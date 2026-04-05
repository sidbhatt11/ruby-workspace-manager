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

## ~~2. `rwm exec`~~ (Dropped)

Shell loops cover ad-hoc commands; anything recurring deserves a Rake task with caching.

## ~~3. Dependency version consistency checking~~ (Dropped)

Bundler already resolves deps per-app; an allowlist for intentional drift would add config against the zero-config philosophy.

## 4. Watch mode

`rwm watch spec` — re-run affected specs when files change. Ruby culture is deeply TDD-oriented, and the feedback loop of "save file → affected specs re-run instantly" is the workflow developers expect from tools like Guard.

**What to investigate:**
- File watching: use `rb-fsevent` (macOS), `rb-inotify` (Linux), or `listen` gem? All are external deps, which conflicts with the zero-dependency philosophy. Alternatively, poll with `stat` on a short interval
- Scope: watch the entire workspace and map changed files to affected packages (reuse `AffectedDetector` logic), then re-run only those
- Debouncing: batch rapid file changes (e.g., save + auto-format) into a single run
- Output: clear screen between runs? Show a summary of what changed and what's re-running?
- Could this be implemented as a thin wrapper that shells out to `fswatch` or `watchman` if available, avoiding a Ruby dependency?

**Goal:** `rwm watch spec` provides a fast TDD feedback loop — change a file in `auth`, specs for `auth` and its dependents re-run automatically.

## ~~5. `rwm why <package>`~~ (Dropped)

Covered by existing `rwm info` (shows deps, dependents, transitive dependents) and `rwm graph`.

## ~~6. Selective bootstrap / multi-package targeting~~ (Done)

Implemented multi-package targeting across `rwm run` and `rwm bootstrap`. `rwm run <task> pkg1 pkg2` runs on exactly those packages. `rwm bootstrap pkg1 pkg2` bootstraps those packages + transitive deps. Root steps always run.
