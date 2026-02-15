# Changelog

All notable changes to Ruby Workspace Manager are documented in this file.

## [Unreleased]

### Added
- Shell completions for Bash and Zsh (`completions/rwm.bash`, `completions/rwm.zsh`)
- `--dry-run` flag for `rwm run` to preview which packages would be executed
- `--base REF` flag for `rwm run --affected` and `rwm affected` to override the auto-detected base branch
- `--verbose` flag and `RWM_DEBUG=1` env var for debug logging across all subsystems
- `rwm cache clean [pkg]` command to clear cached task results
- Ctrl+C signal trapping in the DAG scheduler with clean thread teardown

### Changed
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
- Comprehensive usage guide (GUIDE.md)
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

[Unreleased]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sidbhatt11/ruby-workspace-manager/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sidbhatt11/ruby-workspace-manager/releases/tag/v0.1.0
