[← Back to README](../README.md)

# Command Reference

## Commands

| Command | Description |
|---------|-------------|
| `rwm init [--vscode]` | Initialize a workspace. Creates dirs, Gemfile, Rakefile, .gitignore. Runs bootstrap. Idempotent. |
| `rwm bootstrap [pkg...]` | Install deps, build graph, install hooks, run bootstrap tasks. Scopes to named packages if given. Idempotent. |
| `rwm new <app\|lib> <name> [--test=FW]` | Scaffold a new package. `--test`: `rspec` (default), `minitest`, `none`. |
| `rwm info <name>` | Show package details: type, path, deps, dependents. |
| `rwm graph [--dot\|--mermaid]` | Rebuild dependency graph. Optionally output DOT or Mermaid. |
| `rwm check` | Validate conventions. Exit 0 on pass, 1 on failure. |
| `rwm list` | List all packages. |
| `rwm run <task> [pkg...]` | Run a Rake task across packages. All if none given. |
| `rwm <task> [pkg...]` | Task shortcut: `rwm spec` = `rwm run spec`. |
| `rwm affected [--committed] [--base REF]` | Show affected packages. |
| `rwm cache clean [pkg]` | Clear cached task results. |
| `rwm help` | Show available commands. |
| `rwm version` | Show version. |

## `rwm run` flags

| Flag | Description |
|------|-------------|
| `--affected` | Only run on packages affected by current changes. |
| `--committed` | With `--affected`, only consider committed changes. |
| `--base REF` | With `--affected`, compare against REF instead of auto-detected base. |
| `--dry-run` | Show what would run without executing. |
| `--no-cache` | Bypass task caching. Force all tasks to run. |
| `--buffered` | Buffer output per-package and print on completion. |
| `--concurrency N` | Limit parallel workers. Default: number of CPU cores. |

## VSCode integration

```sh
rwm init --vscode
```

Generates a `.code-workspace` file that configures VSCode's multi-root workspace feature. Each package becomes a separate root folder in the sidebar. After initial creation, `rwm bootstrap` and `rwm new` keep the folder list updated automatically. Existing `settings`, `extensions`, `launch`, and `tasks` keys are preserved.

## Shell completions

RWM ships with completion scripts for Bash and Zsh that provide command, flag, and package name completion.

### Bash

Add to `.bashrc` or `.bash_profile`:

```bash
source "$(gem contents ruby_workspace_manager | grep rwm.bash)"
```

### Zsh

Add to `.zshrc` (before `compinit`):

```zsh
fpath=($(gem contents ruby_workspace_manager | grep completions/rwm.zsh | xargs dirname) $fpath)
autoload -Uz compinit && compinit
```

Both scripts dynamically discover package names by scanning `libs/` and `apps/`, so tab completion always reflects your current workspace.
