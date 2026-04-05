# To Plan

Items to investigate and plan before implementing.

## ~~1. Railtie for automatic Zeitwerk integration~~ (Dropped)

Niche (only Rails dev hot-reload), adds complexity and runtime Rails dependency. Manual `config.autoload_paths` setup is documented and straightforward enough.

## ~~2. `rwm exec`~~ (Dropped)

Shell loops cover ad-hoc commands; anything recurring deserves a Rake task with caching.

## ~~3. Dependency version consistency checking~~ (Dropped)

Bundler already resolves deps per-app; an allowlist for intentional drift would add config against the zero-config philosophy.

## ~~4. Watch mode~~ (Dropped)

Watch/reload is an app-level concern — Rails, Shakapacker, Guard, and Watchman already handle this per-app. Workspace-level watching would either duplicate their work or need a file-watching dependency (breaking zero-dep).

## ~~5. `rwm why <package>`~~ (Dropped)

Covered by existing `rwm info` (shows deps, dependents, transitive dependents) and `rwm graph`.

## ~~6. Selective bootstrap / multi-package targeting~~ (Done)

Implemented multi-package targeting across `rwm run` and `rwm bootstrap`. `rwm run <task> pkg1 pkg2` runs on exactly those packages. `rwm bootstrap pkg1 pkg2` bootstraps those packages + transitive deps. Root steps always run.
