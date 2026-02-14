# RWM — TODO

See [PLAN.md](PLAN.md) for full architecture and design details.

## Phase 1: Core Foundation
- [ ] Gem skeleton (gemspec, bin/rwm, lib/rwm.rb, version, errors)
- [ ] Config loader (.rwm.yml)
- [ ] Workspace discovery + Package model
- [ ] GemfileParser (Bundler DSL path deps)
- [ ] DependencyGraph (TSort DAG, cycle detection)
- [ ] ConventionChecker (structural rules)
- [ ] CLI dispatcher
- [ ] Commands: init, graph, check, list
- [ ] Specs

## Phase 2: Task Execution
- [ ] TaskRunner (sequential + parallel)
- [ ] Commands::Run + task shortcuts
- [ ] Specs

## Phase 3: Affected Detection
- [ ] AffectedDetector (git diff + graph walk)
- [ ] Commands::Affected + --affected flag
- [ ] Specs

## Phase 4: Git Hooks
- [ ] GitHooks (post-commit, pre-push)
- [ ] Commands::Hooks
- [ ] Wire into rwm init
- [ ] Specs
