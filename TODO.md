# TODO

## Performance

- [ ] Cache `rake -P` results per package instead of spawning a process per package per run
- [ ] Consider trying the task and handling failure gracefully instead of pre-checking

## Robustness

- [ ] Trap Ctrl+C signals and clean up child processes in the DAG scheduler
- [ ] Add `--verbose` flag or `RWM_DEBUG=1` env var for logging git commands, cache decisions, graph operations

## Housekeeping

- [ ] Add `rwm cache clean` command or auto-prune stale cache entries on graph rebuild
- [ ] Fix `gem build` warning — drop duplicate `source_code_uri` metadata or add `changelog_uri`

## DX

- [ ] Add `rwm_app` helper or make `rwm_lib` smarter about checking both `libs/` and `apps/`
