[← Back to README](../README.md)

# Bootstrap and Daily Workflow

## What bootstrap does

`rwm bootstrap` gets a workspace into a working state:

1. Runs `bundle install` in the workspace root.
2. Runs `rake bootstrap` in the root (if defined — for binstubs, shared tooling, etc.).
3. Installs git hooks (pre-push runs `rwm check` to [validate conventions](conventions-and-hooks.md), post-commit rebuilds the graph on Gemfile changes).
4. Runs `bundle install` in every package (in parallel).
5. Runs `rake bootstrap` in packages that define it (in parallel).
6. Builds and validates the dependency graph.
7. Updates the `.code-workspace` file if it exists (see [VSCode integration](command-reference.md#vscode-integration)).

Both `rwm init` and `rwm bootstrap` are idempotent.

You can scope bootstrap to specific packages: `rwm bootstrap auth billing` bootstraps only those packages plus their transitive dependencies. Root-level steps always run.

## Parallel installs and Bundler

### What you'll see

Step 4 runs `bundle install` concurrently across packages. If your packages share a gem installation directory (the default), you may see:

```
Waiting for another process to let go of lock /path/to/.bundle/lock...
```

This is safe — Bundler handles it correctly. But it means parallel installs don't give you the speedup you might expect. The installs are effectively serial despite running in separate threads.

### Why this happens

In a monorepo, each package has its own Gemfile, its own dependency resolution, and its own `bundle install`. RWM schedules these in parallel, but they all write to the same shared gem directory — so Bundler serialises them with a file lock.

Package managers with built-in workspace support (npm, Cargo, Go, Python's uv) avoid this by resolving and installing all packages in a single pass. Bundler was designed for single-application projects and doesn't have workspaces, so each package installs independently.

### When it matters (and when it doesn't)

**First bootstrap** (cold cache, all gems need downloading): the serialisation is noticeable. Every package's install contends on the shared gem directory.

**Subsequent bootstraps** (gems already installed): `bundle install` is fast per-package because it just verifies the lockfile. The overhead is minimal.

In practice, bootstrap is a one-time setup cost per machine. If you run it regularly after `git pull`, subsequent runs are fast.

### Opting into per-package isolation (advanced)

If parallel installs are a real bottleneck for your workflow, you can give each package its own gem installation directory by setting `BUNDLE_PATH` per-package:

```sh
# In each package's .bundle/config
---
BUNDLE_PATH: "vendor/bundle"
```

This eliminates the shared lock — each `bundle install` writes to its own `vendor/bundle/`, so they run truly in parallel with no contention.

**Tradeoffs:**

| | Shared (default) | Per-package isolation |
|---|---|---|
| Disk usage | Gems installed once | Gems duplicated per package |
| Parallel install | Serialised (lock contention) | Truly parallel |
| Dependency versions | One version per gem, shared | Packages can diverge silently |
| Setup | Nothing to configure | Needs `.bundle/config` per package |
| gitignore | Nothing extra | Add `vendor/bundle` |

**Why shared is the default:** It works correctly, uses less disk, avoids version drift between packages, and matches how most Ruby projects work. Per-package isolation is an optimisation for large monorepos where first-bootstrap time is a real pain point — not something most workspaces need.

## The bootstrap rake task

Every scaffolded package includes an empty `bootstrap` task. This is where package-specific setup belongs:

```ruby
# libs/auth/Rakefile
task :bootstrap do
  sh "bin/rails db:setup" if File.exist?("bin/rails")
  sh "cp config/credentials.example.yml config/credentials.yml" unless File.exist?("config/credentials.yml")
end
```

Common uses: database setup, copying example config files, generating local certificates, compiling native extensions.

The key property: `rwm bootstrap` runs every package's bootstrap task automatically. Developers don't need to know which packages have special setup — they run one command and everything is handled.

## After cloning

```sh
git clone <repo>
cd <repo>
rwm bootstrap
```

Every package is installed, the graph is built, hooks are active, and the workspace is ready.

## Daily workflow

```sh
git pull --rebase
rwm bootstrap          # picks up any new packages or dependency changes
git checkout -b my-feature
# ... make changes ...
rwm spec               # run all specs
rwm spec --affected    # or just the affected ones
```

The pre-push hook runs `rwm check` automatically. The post-commit hook rebuilds the graph when Gemfiles change.
