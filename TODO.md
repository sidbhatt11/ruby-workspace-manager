# TODO — Issues Found During Manual Testing (v0.6.2)

## Bugs

### 1. Exit code is always 0, even on failure (HIGH)
- `rwm run spec` returns exit code 0 when tests fail
- `rwm info nonexistent` returns exit code 0 with "Error: Package not found"
- `rwm run spec nonexistent` also returns exit code 0
- Docs claim "Exit code is 0 if all pass, 1 if any fail"
- **Impact:** Breaks CI pipelines — a failing test suite won't fail the CI job

### 2. `rwm_lib` silently ignores non-existent libs (MEDIUM)
- `rwm_lib "api"` (an app, not a lib) generates `gem "api", path: ".../libs/api"` even though that path doesn't exist
- `rwm graph` and `rwm check` both silently pass
- `bundle install` and `bundle exec` crash with a `Bundler::PathError`
- Should error at graph/bootstrap time with a clear message like: "Unknown workspace lib: api"

### 3. `rwm affected --base <invalid-ref>` silently returns no affected packages (MEDIUM)
- Using a non-existent base ref doesn't produce an error
- Returns "No packages affected" which is misleading
- A user could typo the base branch and skip all tests in CI

## Improvements

### 4. `--dry-run` doesn't distinguish "would run" vs "would skip (no task)"
- Packages without the requested Rake task are listed as "would run" even though they'd be skipped at runtime
- Could confuse users wondering why the real run executed fewer packages than dry-run listed

### 5. Failure summary should distinguish skip reasons
- Currently: "5 package(s): 1 failed, 4 skipped"
- 2 skipped because they lack the task, 2 skipped because a dependency failed — these are different
- Suggested: "1 failed, 2 skipped (dep failed), 2 skipped (no task)"

### 6. `rwm graph` output could be more informative on first build
- Currently only prints "Graph saved to .rwm/graph.json (5 packages, 8 edges)"
- Consider printing a quick summary of packages (like `rwm list`) on first build or when packages change

### 7. Bundler lock contention during parallel bootstrap
- Saw `Waiting for another process to let go of lock` during `rwm bootstrap` with parallel installs
- Expected with shared gem dirs but could be slow on larger monorepos
- Consider documenting this or adding a `--concurrency` flag to bootstrap
