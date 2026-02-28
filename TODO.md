# TODO — Issues Found During Manual Testing (v0.6.2)

## Bugs

### ~~1. Exit code is always 0, even on failure (HIGH)~~ FIXED
- ~~Fixed in `bin/rwm` — was missing `exit()` call around `CLI.run`~~

### ~~2. `rwm_lib` silently ignores non-existent libs (MEDIUM)~~ FIXED
- ~~`rwm_lib` now validates that `libs/<name>` exists before generating the gem declaration~~

### ~~3. `rwm affected --base <invalid-ref>` silently returns no affected packages (MEDIUM)~~ FIXED
- ~~Now raises `Rwm::Error` when the provided `--base` ref doesn't exist~~

## Improvements

### ~~4. `--dry-run` doesn't distinguish "would run" vs "would skip (no task)"~~ WON'T FIX
- ~~Dry-run runs before the task runner, so it can't know which Rakefiles define the task without executing them. This is inherent to the design.~~

### ~~5. Failure summary should distinguish skip reasons~~ FIXED
- ~~Summary now shows "skipped (dep failed)" vs "skipped (no task)"~~

### ~~6. `rwm graph` output could be more informative on first build~~ FIXED
- ~~Default `rwm graph` now lists each package with its dependencies~~

### ~~7. Bundler lock contention during parallel bootstrap~~ DOCUMENTED
- ~~Added note in README explaining the behavior and workarounds~~
