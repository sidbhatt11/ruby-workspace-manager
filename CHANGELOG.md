# Changelog

All notable changes to Ruby Workspace Manager are documented in this file.

## [Unreleased]

## [0.6.4] - 2026-04-05

### Fixed
- `cacheable_task` now supports Rake dependency syntax — `cacheable_task seed: :environment` works like `task` does ([#1](https://github.com/sidbhatt11/ruby-workspace-manager/issues/1))
- `cacheable_task` replaces existing task actions instead of stacking — no more double spec runs with rspec-rails ([#2](https://github.com/sidbhatt11/ruby-workspace-manager/issues/2))
- Default `rwm graph` output now correctly shows `lib/` prefix for libraries instead of `app/` for everything ([#3](https://github.com/sidbhatt11/ruby-workspace-manager/issues/3))
- Task runner and cache declaration discovery now set `BUNDLE_GEMFILE` to the package's own Gemfile, preventing the root bundle environment from leaking into child processes

### Added
- Multi-package targeting — `rwm run spec auth billing` and `rwm spec auth billing` run on exactly those packages
- Selective bootstrap — `rwm bootstrap auth billing` bootstraps named packages plus their transitive dependencies
- `DependencyGraph#transitive_dependencies` — returns all packages a given package transitively depends on
- `Rwm.bundle_env(dir)` helper for setting `BUNDLE_GEMFILE` when spawning child processes in package directories
- Mutual exclusion between `--affected` and explicit package names (errors if both given)

### Changed
- `cacheable_task` signature changed from `(name, output:)` to `(*args, **opts)` to support all Rake task definition patterns
- CLI help updated to show `[pkg...]` syntax for `run` and `bootstrap`
- README restructured — concise intro/pitch linking to 7 focused docs in `docs/`
- SECURITY.md rewritten with clearer versioning guidance
- WORKFLOW.md updated to reflect documentation split

## [0.6.3] - 2026-03-01

### Fixed
- Exit code always returned 0 even on failure — `bin/rwm` now propagates command return codes to the shell via `exit()`
- `rwm_lib` silently ignored non-existent libraries — now raises a clear error if `libs/<name>` doesn't exist
- `rwm affected --base <invalid-ref>` silently returned no affected packages — now raises `Rwm::Error` when the ref doesn't exist
- Task run summary now distinguishes "skipped (dep failed)" from "skipped (no task)" instead of combining them

### Added
- Subprocess-level tests for `bin/rwm` exit codes
- Default `rwm graph` output now lists each package with its dependencies (when no `--dot`/`--mermaid` flag is given)
- Documentation for Bundler lock contention during parallel bootstrap

## [0.6.2] - 2026-02-28

### Fixed
- Corrected "Rails and Zeitwerk" documentation — `Bundler.require` already auto-requires workspace libs (including transitive deps); manual `Rwm.require_libs` before `require "rails"` was never necessary for standard Rails apps
- Corrected inaccurate claim that Zeitwerk overrides `Kernel#require` — it uses `Module#autoload` and `const_missing`
- Created missing `lib/ruby_workspace_manager.rb` entry point so `Bundler.require` can auto-load the gem
- `Rwm.require_libs` is now idempotent — safe to call multiple times without double-loading
- Thread-safety: `TaskCache#content_hash` now uses a mutex to protect the memoization hash from concurrent access
- `DependencyGraph.load` now gracefully handles deleted or corrupt `graph.json` (catches `Errno::ENOENT` and `JSON::ParserError`) and falls back to rebuilding instead of crashing
- `DependencyGraph.load` now skips stale edges referencing packages that no longer exist in the workspace, instead of creating ghost entries in the graph
- `TaskRunner` now suppresses `IOError` noise when threads are killed during Ctrl+C — previously printed confusing `stream closed in another thread` messages to stderr

### Added
- `Rwm.workspace_root` — module-level accessor, cached during Gemfile evaluation
- `Rwm.lib_path(name)` — returns the load path for a workspace lib (e.g. for `config.autoload_paths` in Rails)
- `Rwm.libs_required?` — predicate to check if workspace libs have been loaded
- Comprehensive Rails guide in README covering traditional vs Zeitwerk-compatible lib structure, the practical extraction workflow, and trade-offs for each approach

## [0.6.1] - 2026-02-20

### Changed
- Lowered Ruby version floor from 3.4 to 3.2 — no code changes needed, CI passes on 3.2, 3.3, 3.4, and 4.0
- CI now tests against Ruby 3.2, 3.3, 3.4, and 4.0

## [0.6.0] - 2026-02-20

### Added
- `--test` option for `rwm new` — choose between `rspec` (default), `minitest`, or `none` for scaffolded test infrastructure
- Parallel cache declaration discovery — preloads task declarations across packages using threads for faster `rwm run` startup
- File locking on `.rwm/graph.json` — shared locks for reads, exclusive locks for writes, safe for concurrent `rwm` processes
- Custom affected ignore patterns via `.rwm/affected_ignore` — one glob per line, merged with built-in defaults
- Built-in ignore patterns for affected detection — `*.md`, `LICENSE*`, `CHANGELOG*`, `.github/**`, `.vscode/**`, `.idea/**`, `docs/**`, `.rwm/**` no longer trigger full workspace runs

### Changed
- `rwm init` now detects the git root via `git rev-parse --show-toplevel` instead of using the current directory — works correctly from subdirectories
- `execution_levels` uses `Set` instead of `Array` for O(V+E) performance instead of O(V^3)
- CLI flags (`--no-cache`, `--affected`, etc.) now work in any position — `rwm run spec --no-cache` and `rwm --no-cache run spec` are both valid
- Root Gemfile template from `rwm init` now includes `rake` for consistency with package Gemfiles
- Consolidated README and GUIDE into a single comprehensive README
- Security policy updated: only latest release supported until 1.0

### Fixed
- CLI now catches `Interrupt` (exit 130) and unexpected `StandardError` (friendly message, backtrace in verbose mode) instead of printing raw backtraces
- `NO_TASK_PATTERN` broadened to handle case variations and locale differences in Rake's "task not found" message
- `Rwm.resolved_libs` no longer leaks duplicate entries from `scan_transitive_deps` sandbox
- Thread deadlock in DAG scheduler — replaced `Result` boolean fields with status enum

## [0.5.0] - 2026-02-15

### Added
- Transitive dependency resolution in `rwm_lib` — declaring `rwm_lib "auth"` now automatically adds auth's workspace dependencies (e.g. `core`) to the bundle
- `Rwm.require_libs` helper (`require "rwm/rails"`) — one-liner for Rails `config/application.rb` that requires all workspace libs before Zeitwerk loads

## [0.4.0] - 2026-02-15

### Added
- `rwm run` summary line after task execution showing passed/failed/skipped counts (e.g. `3 package(s): 2 passed, 1 skipped.`)
- Verbose debug output lists individual package names for passed and skipped categories
- Shell completions for Bash and Zsh (`completions/rwm.bash`, `completions/rwm.zsh`)
- `--dry-run` flag for `rwm run` to preview which packages would be executed
- `--base REF` flag for `rwm run --affected` and `rwm affected` to override the auto-detected base branch
- `--verbose` flag and `RWM_DEBUG=1` env var for debug logging across all subsystems
- `rwm cache clean [pkg]` command to clear cached task results
- Ctrl+C signal trapping in the DAG scheduler with clean thread teardown
- Command-level integration tests for all command files (list, info, check, graph, new, cache, affected, run, init)

### Changed
- Any unrecognized command is now treated as a task name: `rwm test` = `rwm run test`, `rwm lint` = `rwm run lint` (replaces fixed `test`/`spec`/`build` shortcuts)
- App scaffolding (`rwm new app`) now uses `app/` instead of `lib/` for source code, with `require_paths = ["app"]` in the generated gemspec
- Task cache now uses `git ls-files` for source file discovery instead of directory globbing, automatically respecting `.gitignore`
- Task runner now uses try-and-handle approach: runs all packages with a Rakefile and gracefully skips those missing the requested task, instead of pre-checking with `rake -P`
- Removed dead code: `Package#rake_tasks`, `Package#has_rake_task?`, `Package#gemspec_path`, `Package#to_s`, `Workspace#libs_dir`, `Workspace#apps_dir`, `DependencyGraph.load_from_file`

### Fixed
- `CycleError` raised with wrong argument format from `topological_order` and `execution_levels`, causing `NoMethodError` on cyclic dependency graphs
- Race condition in DAG scheduler where `pending.empty?` was checked outside the mutex
- `gem build` warning about duplicate `homepage_uri` / `source_code_uri` metadata

## [0.3.0] - 2025-05-01

### Added
- Startup checks for required tools (`git`, `bundle`) with clear error messages
- Specs for error paths and edge cases across the codebase
- SECURITY.md with supported versions and vulnerability reporting instructions

### Changed
- All backtick shell commands replaced with `Open3.capture3` for safety and proper error handling
- CodeQL action upgraded from v3 to v4

### Fixed
- Silent cache corruption when a dependency package is missing from the workspace

## [0.2.0] - 2025-04-01

### Added
- DAG-based parallel scheduler replacing level-based execution
- Opt-in task caching with content hashing and transitive invalidation
- Gemfile DSL (`rwm_lib`) and Rake DSL (`cacheable_task`) for workspace conventions
- Affected package detection with `rwm affected` and `rwm run --affected`
- `--committed` flag to limit affected detection to committed changes only
- `--buffered` flag for per-package output buffering
- Single-package runs: `rwm test <name>`
- Graph visualization: `rwm graph --dot` and `rwm graph --mermaid`
- VSCode `.code-workspace` file generation
- Overcommit integration and plain git hooks fallback
- Auto-loading cached dependency graph with staleness detection
- Comprehensive usage guide (consolidated into README in v0.6.0)
- CI pipeline with security scanning (bundler-audit, CodeQL)

### Changed
- Gem renamed from `rwm` to `ruby_workspace_manager`
- Target Ruby version set to 3.4+
- Scaffolded packages include rake and rspec as dev dependencies

### Fixed
- `has_rake_task?` now uses `rake -P` instead of nonexistent `--task-check` flag
- Missing `require "fileutils"` in `DependencyGraph#save`
- Various documentation inconsistencies

## [0.1.0] - 2025-03-01

### Added
- Initial release
- Core workspace detection using git root
- Package discovery in `libs/` and `apps/` directories
- Dependency graph built from Gemfile path references
- Convention checker for structural validation
- CLI with `init`, `bootstrap`, `new`, `info`, `graph`, `check`, `list`, and `run` commands
- Task shortcuts: `rwm test`, `rwm spec`, `rwm build`

[Unreleased]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.6.4...HEAD
[0.6.4]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sidbhatt11/ruby-workspace-manager/releases/tag/v0.1.0
