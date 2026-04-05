[← Back to README](../README.md)

# Getting Started

## New workspace

```sh
gem install ruby_workspace_manager

mkdir my-project && cd my-project
git init
rwm init
```

`rwm init` creates the full workspace structure — `libs/`, `apps/`, a root Gemfile (with `rake` and `ruby_workspace_manager`), a root Rakefile, and adds `.rwm/` to `.gitignore`. It then runs `rwm bootstrap` automatically. The command is idempotent.

## Existing project

If you already have a git repo with a Gemfile, add RWM to it and initialize:

```sh
bundle add ruby_workspace_manager
rwm init
```

`rwm init` won't overwrite your existing Gemfile or Rakefile — it only creates files that are missing.

## Creating packages

```sh
rwm new lib auth
rwm new lib billing
rwm new app api
```

Each command scaffolds a complete gem structure: Gemfile, gemspec, Rakefile, module stub, and test helper (unless `--test=none`).

### Scaffolding options

```sh
rwm new lib <name>
rwm new app <name>
rwm new lib <name> --test=minitest
rwm new app <name> --test=none
```

Package names must match `/\A[a-z][a-z0-9_]*\z/` (lowercase, letters/digits/underscores, starts with a letter).

The `--test` flag controls which test framework is scaffolded. Values: `rspec` (default), `minitest`, `none`.

The scaffold includes:

- **Gemfile** — Sources rubygems.org, loads the gemspec, includes development dependencies (`rake`, the chosen test gem, `ruby_workspace_manager`), and requires `rwm/gemfile` for the `rwm_lib` helper.
- **Gemspec** — Minimal spec. Libraries use `require_paths = ["lib"]` and declare `spec.files`; applications use `require_paths = ["app"]` and omit `spec.files`.
- **Rakefile** — A `cacheable_task` for the test framework (`:spec` for rspec, `:test` for minitest) plus an empty `:bootstrap` task. With `--test=none`, only the bootstrap task is generated. (`cacheable_task` enables [task caching](running-tasks.md#task-caching) — it works like a normal Rake `task` but RWM can skip it when inputs haven't changed.)
- **Source file** — `lib/<name>.rb` for libraries, `app/<name>.rb` for applications. Module stub.
- **Test helper** — `spec/spec_helper.rb` for rspec, `test/test_helper.rb` for minitest. Omitted with `--test=none`.

### Inspecting and listing

```sh
rwm info auth     # type, path, dependencies, direct/transitive dependents
rwm list          # formatted table of all packages
```

## Declaring dependencies

Edit the consuming package's Gemfile:

```ruby
# apps/api/Gemfile
require "rwm/gemfile"

rwm_lib "auth"
rwm_lib "billing"
```

Then bootstrap to install deps and rebuild the graph:

```sh
rwm bootstrap
```

### How dependency detection works

RWM reads each package's Gemfile using Bundler's DSL parser and extracts gems declared with a `path:` option pointing into the workspace. It does not scan source code for `require` statements. This means Bundler's Gemfile is the single source of truth for both runtime resolution and RWM's dependency graph.

### The `rwm_lib` helper

Scaffolded packages include `require "rwm/gemfile"` in their Gemfile, which adds the `rwm_lib` method to Bundler's DSL:

```ruby
# libs/billing/Gemfile
require "rwm/gemfile"

rwm_lib "auth"
```

This expands to:

```ruby
gem "auth", path: "/absolute/path/to/libs/auth"
```

The workspace root is resolved via `git rev-parse --show-toplevel`, so it works regardless of where you run the command. You can pass any extra options that `gem` accepts:

```ruby
rwm_lib "auth", require: false
```

There is no `rwm_app` helper. Applications are leaf nodes — nothing should depend on them.

`rwm_lib` validates that the library directory exists. If you reference a library that hasn't been created yet, you'll get a clear error:

```
rwm_lib 'payments': no library found at libs/payments.
Libraries must live in libs/. Create one with: rwm new lib payments
```

You can also use raw `gem ... path:` syntax directly. Both work identically for dependency detection.

### Transitive resolution

When you call `rwm_lib "auth"`, RWM automatically resolves auth's own workspace dependencies. If auth's Gemfile declares `rwm_lib "core"`, then `core` is added to your bundle automatically.

This works recursively. Diamond dependencies are handled safely (each lib is resolved at most once). Circular dependencies are caught by `rwm check` — see [Conventions and Hooks](conventions-and-hooks.md).

```ruby
# apps/web/Gemfile — only the direct dep is needed
require "rwm/gemfile"

rwm_lib "auth"    # core (auth's dep) is added automatically
```

Transitive resolution uses `Bundler::Dsl.eval_gemfile` — the same mechanism Bundler uses internally. Options passed to the direct `rwm_lib` call (like `group:` or `require:`) are not forwarded to transitive deps.

## The dependency graph

### Building

```sh
rwm graph
```

Parses every package's Gemfile, constructs a DAG using Ruby's `TSort` module (Tarjan's algorithm), writes it to `.rwm/graph.json`, and prints a summary.

### Caching and staleness

Most commands (`run`, `list`, `check`, `affected`, `info`) load the graph from `.rwm/graph.json` rather than re-parsing Gemfiles. If any package's Gemfile has a modification time newer than the cache file, the graph is silently rebuilt. You rarely need to run `rwm graph` manually.

Concurrent `rwm` processes are safe — graph reads use shared file locks and writes use exclusive file locks.

### Visualization

```sh
rwm graph --dot      # Graphviz DOT format
rwm graph --mermaid  # Mermaid flowchart format
```

Pipe DOT output to Graphviz to render an image:

```sh
rwm graph --dot | dot -Tpng -o graph.png
```

Or paste Mermaid output into any Mermaid-compatible renderer (GitHub markdown, Mermaid Live Editor, etc.).
