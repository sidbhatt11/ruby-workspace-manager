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

## Phase 5: Task Caching (opt-in)
- [ ] TaskCache (content-hash, redo-style)
- [ ] Wire `--cache` into `rwm run`
- [ ] Specs
