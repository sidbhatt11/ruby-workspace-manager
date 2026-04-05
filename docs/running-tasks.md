[← Back to README](../README.md)

# Running Tasks

## Basic usage

```sh
rwm run <task>              # run in all packages
rwm run <task> auth         # run in one package
rwm run <task> auth billing # run in specific packages
rwm spec                    # shortcut for `rwm run spec`
rwm lint auth               # shortcut for `rwm run lint auth`
```

Any command that isn't a built-in subcommand is treated as a task name and forwarded to `rwm run`.

RWM runs `bundle exec rake <task>` in each package directory that has a Rakefile. Packages that don't define the requested task are automatically detected and silently skipped.

## Parallel execution

RWM uses a DAG scheduler with a thread pool. Each package starts executing the instant all of its dependencies have completed. If A and B are independent, they run simultaneously. If C depends on A, C starts as soon as A finishes — it does not wait for B.

The default concurrency is `Etc.nprocessors` (number of CPU cores). Override with:

```sh
rwm run spec --concurrency 4
```

## Output modes

**Streaming (default)** — Output is printed as it happens, prefixed with the package name:

```
[auth] 5 examples, 0 failures
[billing] 3 examples, 0 failures
```

**Buffered** — Each package's output is collected and printed as a complete block when it finishes. Failed packages have their output sent to stderr:

```sh
rwm run spec --buffered
```

## Failure handling

When a package fails, its transitive dependents are immediately skipped. Unrelated packages continue running. The exit code is 0 if all packages pass, 1 if any fail.

The summary distinguishes between skip reasons:

```
5 package(s): 2 passed, 1 failed, 1 skipped (dep failed), 1 skipped (no task).
```

- **skipped (dep failed)** — a dependency failed, so this package was not attempted
- **skipped (no task)** — the package's Rakefile doesn't define the requested task

## Task caching

### Why caching matters

In a monorepo with many packages, most runs touch only a few. Without caching, `rwm spec` re-runs everything even if nothing changed. Task caching skips packages whose inputs are unchanged.

### Content-hash caching

RWM's cache is inspired by [DJB's redo](https://cr.yp.to/redo.html). The core insight: **use content hashes, not timestamps, to decide what needs rebuilding.** Timestamps are fragile — `git checkout` changes them, rebasing rewrites them. Content hashes are deterministic: if the bytes haven't changed, the result is still valid.

For each (package, task) pair, RWM:

1. **Computes a content hash** — SHA256 of all source files in the package (sorted by path), plus the content hashes of all dependency packages.
2. **Compares with stored hash** — If the hash matches the last successful run and declared outputs exist, the task is skipped.
3. **Stores on success** — After a successful run, the hash is saved to `.rwm/cache/<package>-<task>`.

Source files are discovered via `git ls-files` (tracked + untracked-but-not-ignored), so anything in `.gitignore` is excluded from the hash.

### Transitive invalidation

A package's content hash includes the content hashes of its dependencies, recursively:

```
hash(auth)    = SHA256(auth's files)
hash(billing) = SHA256(billing's files + hash(auth))
hash(api)     = SHA256(api's files + hash(billing) + hash(auth))
```

Change a single file in `auth` and the hashes of `billing` and `api` change automatically. No explicit invalidation logic needed.

### Where the cache is coarser than redo

True redo tracks exactly which files a build step read during execution. RWM hashes every git-tracked file in the package directory. This means editing a README invalidates the spec cache even though RSpec never reads it.

This is a deliberate tradeoff. File-level read tracking would require filesystem interception (`strace`, `dtrace`, FUSE), which contradicts the zero-dependency philosophy. Package-level hashing may give false invalidations (unnecessary re-runs) but never false cache hits (skipping when it shouldn't).

### Declaring cacheable tasks

Tasks are only cached if declared with `cacheable_task` in the Rakefile. This requires `rwm/rake`, which is already included in scaffolded Rakefiles:

```ruby
# libs/auth/Rakefile
require "rwm/rake"

cacheable_task :spec do
  sh "bundle exec rspec"
end

cacheable_task :build, output: "pkg/*.gem" do
  sh "gem build *.gemspec"
end
```

`cacheable_task` creates a normal Rake task — it works like `task` when run directly. The caching metadata is only used when RWM orchestrates the run.

The optional `output:` parameter declares a glob for expected output files. If declared outputs don't exist, the cache is invalid even if the input hash matches.

Tasks declared with plain `task` always run unconditionally.

### Bypassing and clearing the cache

Skip caching for a single run:

```sh
rwm run spec --no-cache
```

Clear stored cache entries entirely:

```sh
rwm cache clean          # clear all cached results
rwm cache clean auth     # clear cache for one package
```

### Sharing the cache

The `.rwm/` directory is gitignored by design — committing it would create constant merge conflicts as the cache and graph change with every task run. Instead, treat your main branch CI as the single source of truth and distribute the cache from there.

Cache entries are content hashes with no absolute paths or machine-specific data. They're fully portable across machines. Restoring a stale cache is always safe — stale entries won't match and the task simply re-runs.

**The pattern:**

1. Main branch CI runs the full test suite, producing a complete `.rwm/` cache.
2. Feature branch CI restores main's cache, then runs only `--affected` packages.
3. Developer machines download the cache during `rwm bootstrap`, so new branches start pre-warmed.

The result: feature branch CI and local development only run what actually changed.

#### GitHub Actions

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Fetch base branch for affected detection
        if: github.ref != 'refs/heads/main'
        run: git fetch origin main --depth=1

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true

      - name: Restore RWM cache
        uses: actions/cache@v4
        with:
          path: .rwm
          key: rwm-${{ runner.os }}-${{ github.sha }}
          restore-keys: rwm-${{ runner.os }}-

      - name: Bootstrap
        run: bundle exec rwm bootstrap

      - name: Run specs
        run: |
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            bundle exec rwm run spec
          else
            bundle exec rwm run spec --affected
          fi

      # Make cache available for local dev bootstrap
      - name: Upload RWM cache
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: rwm-cache
          path: .rwm/
          retention-days: 30
```

Key points:

- **Fetch base branch** — Affected detection runs `git diff main...HEAD`, which needs the base branch ref. A shallow fetch of `main` is enough — no need for `fetch-depth: 0` or a full clone.
- **`actions/cache`** — Caches created on the default branch are accessible to all feature branches. The `restore-keys` prefix picks up the most recent main cache automatically.
- **Main runs everything**, populating a complete cache. Feature branches run only `--affected` and skip anything already cached from main.
- **`upload-artifact`** on main makes the cache downloadable for local dev bootstrap (see below).

#### Local developer cache (optional)

Add a cache download step to your root Rakefile so `rwm bootstrap` warms the local cache automatically:

```ruby
# Rakefile
task :bootstrap do
  restore_rwm_cache
end

def restore_rwm_cache
  return if File.directory?(".rwm/cache")
  return unless system("which gh > /dev/null 2>&1")

  puts "Downloading RWM cache from CI..."
  run_id = `gh run list --branch main --status success --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId'`.strip
  if run_id.empty?
    puts "No CI cache found. Skipping."
    return
  end

  system("gh", "run", "download", run_id, "--name", "rwm-cache", "--dir", ".rwm")
  puts File.directory?(".rwm/cache") ? "Cache restored." : "Cache download failed. Continuing without cache."
end
```

The example above uses the [GitHub CLI](https://cli.github.com/) (`gh`) to download artifacts — your setup may look different depending on your CI provider or storage backend (S3, GCS, etc.). The idea is the same: download the `.rwm/` directory from a known location during bootstrap.

After cloning and running `rwm bootstrap`, developers have a warm cache. Creating a feature branch from main and running `rwm run spec --affected` skips unchanged packages immediately.
