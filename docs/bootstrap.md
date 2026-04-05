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

**Note on parallel installs:** Step 4 runs `bundle install` concurrently across packages. If your packages share a gem installation directory (the default), you may see Bundler log `Waiting for another process to let go of lock`. This is normal — Bundler serializes writes to the shared directory automatically. On large monorepos with many packages, this can slow down bootstrap. If this becomes a bottleneck, consider using `BUNDLE_PATH` per-package or running bootstrap sequentially.

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
