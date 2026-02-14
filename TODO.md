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
- [x] `lib/rwm/gemfile.rb` (rwm_lib / rwm_app helpers)
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
