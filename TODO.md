# RWM — TODO

See [PLAN.md](PLAN.md) for full architecture and design details.

## Phase 1: Core Foundation
- [ ] Gem skeleton (gemspec, bin/rwm, lib/rwm.rb, version, errors)
- [ ] Workspace discovery (find `.rwm/` dir) + Package model
- [ ] GemfileParser (Bundler DSL path deps)
- [ ] DependencyGraph (TSort DAG, cycle detection)
- [ ] ConventionChecker (structural rules)
- [ ] CLI dispatcher
- [ ] Commands: init, bootstrap, graph, check, list
- [ ] Commands: new (app/lib scaffolding), info
- [ ] Specs

## Phase 2: Task Execution
- [ ] TaskRunner (parallel by execution level)
- [ ] Commands::Run + task shortcuts
- [ ] Specs

## Phase 3: Affected Detection
- [ ] AffectedDetector (git diff + graph walk)
- [ ] Commands::Affected + --affected flag
- [ ] Specs

## Phase 4: Overcommit Integration
- [ ] Overcommit setup + hook config
- [ ] Wire into rwm init
- [ ] Specs
