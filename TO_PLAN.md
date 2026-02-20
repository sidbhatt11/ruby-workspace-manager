# To Plan

Items to investigate and plan before implementing.

## ~~1. Lower the Ruby version floor~~ (Done)

Lowered from 3.4 to 3.2. CI passes on 3.2, 3.3, 3.4, and 4.0 with no code changes.

## 2. Railtie for automatic Zeitwerk integration

Currently, Rails users must manually edit `config/application.rb` to add `require "rwm/rails"` and `Rwm.require_libs` before `require "rails"`. This is documented but easy to get wrong — the ordering is fragile and the failure mode (Zeitwerk `LoadError`) is confusing.

**What to investigate:**
- Can a Railtie's `before_configuration` or `before_initialize` hook run early enough (before Zeitwerk activates) to require workspace libs?
- If not, can we use a Bundler plugin or `require` hook that fires during `Bundler.setup`?
- Look at how other gems solve the "must load before Zeitwerk" problem
- Determine if we can detect workspace libs automatically from `Rwm.resolved_libs` without any user code in `application.rb`
- Consider backwards compatibility — the manual approach should still work for users who prefer explicit control

**Goal:** `gem "ruby_workspace_manager"` in the Gemfile is all a Rails app needs. No manual `application.rb` edits. Workspace libs are required automatically at the right point in the boot sequence.

## 3. `rwm exec` — run arbitrary commands across packages

`rwm run` only runs Rake tasks. But a lot of ad-hoc monorepo work is just "run this command in every package" — `bundle outdated`, `ruby -v`, `wc -l lib/**/*.rb`, etc. Having to define a Rake task for each one-off command is friction.

**What to investigate:**
- Command design: `rwm exec "bundle outdated"` or `rwm exec -- bundle outdated`? The `--` separator is more conventional for passing through arguments
- Should it support all the same flags as `rwm run` (`--affected`, `--concurrency`, `--buffered`)?
- Should it respect the dependency graph for ordering, or just run in parallel with no ordering? Probably no ordering needed since these are typically read-only/informational
- Error handling: fail-fast vs. continue-on-error? Probably continue and summarize at the end
- Caching: almost certainly no — exec commands are ad-hoc by nature

**Goal:** `rwm exec -- bundle outdated` runs the command in every package directory, with output prefixed by package name. Supports `--affected` and `--concurrency` for filtering and parallelism.

## 4. Dependency version consistency checking

A common monorepo pain point is version drift — one package pins `pg ~> 1.4` while another uses `pg ~> 1.5`. This silently bites you when packages are deployed together but were developed against different dependency versions. `rwm check` currently validates graph structure but doesn't look at gem versions.

**What to investigate:**
- Parse all package Gemfiles and Gemfile.locks for external gem versions
- Define what "inconsistent" means: different version constraints for the same gem? Or different resolved versions in lockfiles?
- Should this be part of `rwm check` (fail CI) or a separate `rwm audit` / `rwm versions` command (informational)?
- How to handle intentional version differences (e.g., a package migrating to a newer version)?
- Should there be an allowlist/ignorelist for known acceptable drift?

**Goal:** Surface version inconsistencies across packages so teams can catch drift early. Likely a new flag on `rwm check` (e.g., `rwm check --versions`) so it integrates with the existing pre-push hook.

## 5. Watch mode

`rwm watch spec` — re-run affected specs when files change. Ruby culture is deeply TDD-oriented, and the feedback loop of "save file → affected specs re-run instantly" is the workflow developers expect from tools like Guard.

**What to investigate:**
- File watching: use `rb-fsevent` (macOS), `rb-inotify` (Linux), or `listen` gem? All are external deps, which conflicts with the zero-dependency philosophy. Alternatively, poll with `stat` on a short interval
- Scope: watch the entire workspace and map changed files to affected packages (reuse `AffectedDetector` logic), then re-run only those
- Debouncing: batch rapid file changes (e.g., save + auto-format) into a single run
- Output: clear screen between runs? Show a summary of what changed and what's re-running?
- Could this be implemented as a thin wrapper that shells out to `fswatch` or `watchman` if available, avoiding a Ruby dependency?

**Goal:** `rwm watch spec` provides a fast TDD feedback loop — change a file in `auth`, specs for `auth` and its dependents re-run automatically.

## 6. `rwm why <package>`

When `rwm affected` flags a package you didn't expect, there's no way to understand why without mentally tracing the dependency graph. This is especially confusing in large workspaces with deep transitive chains.

**What to investigate:**
- Two use cases: "why is X affected?" (trace from changed files → package → dependents) and "why does X depend on Y?" (shortest path in the dependency graph)
- Output format: a chain like `auth (changed) → billing (depends on auth) → api (depends on billing)`
- Should it integrate with `rwm affected --why` or be a standalone `rwm why` command?
- For dependency chains: use BFS on the graph to find the shortest path between two packages

**Goal:** `rwm why billing` explains "billing is affected because auth changed, and billing depends on auth." `rwm why api auth` shows the dependency path from api to auth.

## 7. Selective bootstrap

`rwm bootstrap` installs and sets up every package in the workspace. After adding a single dependency to one package, you shouldn't have to wait for the entire workspace to re-bootstrap.

**What to investigate:**
- `rwm bootstrap auth billing` — only run `bundle install` and `rake bootstrap` for the named packages (and their dependencies, transitively?)
- Should it also install transitive dependents? If you bootstrap `auth` and `billing` depends on `auth`, should `billing` get a `bundle install` too?
- How does this interact with the root-level bootstrap steps (root `bundle install`, hook installation, graph rebuild)?
- Maybe: root steps always run, package steps are filtered. Or add a `--skip-root` flag

**Goal:** `rwm bootstrap auth` installs deps and runs bootstrap for `auth` (and its dependencies) without touching unrelated packages. Root-level steps still run.
