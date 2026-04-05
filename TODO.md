# TODO

## Bugs

(none)

## Resolved (v0.6.4)

### ~~1. `cacheable_task` doesn't support Rake dependency syntax (MEDIUM)~~ FIXED — [#1](https://github.com/sidbhatt11/ruby-workspace-manager/issues/1)
- ~~Changed signature from `(name, output:)` to `(*args, **opts)` and delegated to `Rake.application.resolve_args`~~

### ~~2. `cacheable_task` stacks actions on existing Rake tasks instead of replacing (MEDIUM)~~ FIXED — [#2](https://github.com/sidbhatt11/ruby-workspace-manager/issues/2)
- ~~`cacheable_task` now calls `clear_actions` on existing tasks before defining~~

### ~~3. Default `rwm graph` output shows all packages as `app/` (LOW)~~ FIXED — [#3](https://github.com/sidbhatt11/ruby-workspace-manager/issues/3)
- ~~Changed `pkg.type == "lib"` to `pkg.lib?`~~

## Resolved (v0.6.2–v0.6.3)

### ~~2. Exit code is always 0, even on failure (HIGH)~~ FIXED
- ~~Fixed in `bin/rwm` — was missing `exit()` call around `CLI.run`~~

### ~~3. `rwm_lib` silently ignores non-existent libs (MEDIUM)~~ FIXED
- ~~`rwm_lib` now validates that `libs/<name>` exists before generating the gem declaration~~

### ~~4. `rwm affected --base <invalid-ref>` silently returns no affected packages (MEDIUM)~~ FIXED
- ~~Now raises `Rwm::Error` when the provided `--base` ref doesn't exist~~

## Improvements

### ~~5. `--dry-run` doesn't distinguish "would run" vs "would skip (no task)"~~ WON'T FIX
- ~~Dry-run runs before the task runner, so it can't know which Rakefiles define the task without executing them. This is inherent to the design.~~

### ~~6. Failure summary should distinguish skip reasons~~ FIXED
- ~~Summary now shows "skipped (dep failed)" vs "skipped (no task)"~~

### ~~7. `rwm graph` output could be more informative on first build~~ FIXED
- ~~Default `rwm graph` now lists each package with its dependencies~~

### ~~8. Bundler lock contention during parallel bootstrap~~ DOCUMENTED
- ~~Added note in README explaining the behavior and workarounds~~
