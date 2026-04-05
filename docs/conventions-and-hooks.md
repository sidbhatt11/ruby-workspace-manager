[← Back to README](../README.md)

# Conventions and Git Hooks

## Convention enforcement

```sh
rwm check
```

Three rules:

1. **No library depending on an application.** Libraries are shared building blocks and must not be coupled to deployment targets.
2. **No application depending on another application.** Applications are independent deployment units. Shared code should be extracted into a library.
3. **No circular dependencies.** Cycles make build ordering impossible and indicate tangled responsibilities.

Exits 0 on pass, 1 on violation. The pre-push hook runs this automatically.

## Git hooks

RWM installs two hooks during `rwm bootstrap`:

- **pre-push** — Runs `rwm check` to validate conventions before pushing. Blocks the push on failure.
- **post-commit** — Runs `rwm graph` if any Gemfile was changed in the commit. Keeps the cached graph in sync.

## Overcommit integration

If `.overcommit.yml` exists, RWM integrates with [Overcommit](https://github.com/sds/overcommit) — it merges hook configuration into the YAML file and creates executable hook scripts. Without Overcommit, RWM writes directly to `.git/hooks/`, appending to existing hooks rather than overwriting.
