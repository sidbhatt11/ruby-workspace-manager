[← Back to README](../README.md)

# Affected Detection

## What "affected" means

When you change code on a feature branch, the affected packages are those you directly changed plus every package that depends on them, transitively. If you change `libs/auth/` and `libs/billing/` depends on `auth` and `apps/api/` depends on `billing`, all three are affected.

## Viewing affected packages

```sh
rwm affected
```

## Running tasks on affected packages

```sh
rwm run spec --affected
```

This is the most useful command for feature branch CI. It combines affected detection with task execution — only affected packages are tested, in correct dependency order with full parallelism.

## How change detection works

By default, RWM considers all uncommitted work plus committed branch changes. It detects changes from three sources, combined:

1. **Committed changes** — `git diff --name-only <base>...HEAD`
2. **Staged changes** — `git diff --name-only --cached`
3. **Unstaged changes** — `git diff --name-only`

Changed files are mapped to packages by path prefix. This means `rwm affected` run locally will include your in-progress edits. Use `--committed` to only consider committed changes (ignoring staged and unstaged) — useful in CI:

```sh
rwm run spec --affected --committed
```

## Root-level changes

Changes to files outside any package directory are treated conservatively. Most inert root files are automatically ignored — the following patterns never trigger affected detection:


- `*.md`, `LICENSE*`, `CHANGELOG*`
- `.github/**`, `.vscode/**`, `.idea/**`
- `docs/**`, `.rwm/**`

Any other root-level change (like the root `Gemfile` or `Rakefile`) marks all packages as affected, since these files can influence the entire workspace.

You can add custom patterns in `.rwm/affected_ignore` (one glob per line, `#` for comments).

## Base branch auto-detection

RWM detects the base branch by reading `git symbolic-ref refs/remotes/origin/HEAD`, falling back to checking for `main` or `master` locally. Override with:

```sh
rwm affected --base develop
rwm run spec --affected --base develop
```

If the provided `--base` ref doesn't exist, RWM errors immediately instead of silently returning no affected packages.
