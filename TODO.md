# RWM — TODO

See [PLAN.md](PLAN.md) for full architecture and design details.

## Phase 1: Core Foundation
- [x] Gem skeleton (gemspec, bin/rwm, lib/rwm.rb, version, errors)
- [x] Workspace discovery (git root) + Package model
- [x] GemfileParser (Bundler DSL path deps)
- [x] DependencyGraph (TSort DAG, cycle detection)
- [x] ConventionChecker (structural rules)
- [x] CLI dispatcher
- [x] Commands: init, bootstrap, graph, check, list
- [x] Commands: new (app/lib scaffolding), info
- [x] Specs

## Phase 2: Task Execution
- [x] TaskRunner (parallel by execution level)
- [x] Commands::Run + task shortcuts
- [x] Upgrade bootstrap to use TaskRunner
- [x] Specs

## Phase 3: Affected Detection
- [x] AffectedDetector (git diff + graph walk)
- [x] Commands::Affected + --affected flag
- [x] Specs

## Phase 4: Overcommit Integration
- [x] Overcommit setup + hook config
- [x] Wire into rwm init
- [x] Specs

## Phase 5: Task Caching
- [x] TaskCache (content-hash, redo-style)
- [x] Wire caching into `rwm run`
- [x] Specs

## Phase 6: Gemfile DSL
- [x] rwm as dev dependency in scaffolded packages
- [x] `lib/rwm/gemfile.rb` (rwm_lib helper)
- [x] Update `rwm new` scaffold
- [x] Specs

## Phase 7: Rakefile DSL + Task-level Caching
- [x] `lib/rwm/rake.rb` (cacheable_task DSL)
- [x] Update TaskCache for task-level opt-in + output checking
- [x] Replace --cache with --no-cache in Commands::Run
- [x] Update `rwm new` scaffold
- [x] Specs

## Enhancements
- [x] VSCode `.code-workspace` file generation (init/bootstrap/new)
- [x] Make overcommit opt-in; always install git hooks (plain or overcommit)
- [x] Make VSCode workspace opt-in (`rwm init --vscode`)
- [x] Remove `rwm_app` from Gemfile DSL (apps can't be depended on)
- [x] Graph visualization (`rwm graph --dot` / `rwm graph --mermaid`)
- [x] GitHub Actions CI workflow
- [x] Load dependency graph from cached `graph.json` instead of rebuilding (`DependencyGraph.load`)
- [x] Avoid double graph build in bootstrap

## Phase 8: Hardening

- [ ] Graph staleness detection — `DependencyGraph.load` auto-rebuilds when any Gemfile is newer than `graph.json`
- [ ] Buffered task output — print per-package output on completion instead of interleaving
- [ ] Replace `exit 1` in bootstrap with exceptions (`BootstrapError`)
- [ ] Specs

## Phase 9: DAG Scheduler

- [ ] Replace execution-level scheduling with a ready-set DAG scheduler
- [ ] Configurable concurrency (`--concurrency N`, default: processor count)
- [ ] Update bootstrap to use DAG scheduler
- [ ] Specs
