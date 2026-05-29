# RWM — TODO

The single working backlog for `ruby-workspace-manager`. Supersedes the old
`TODO.md` + `RWM_IMPROVEMENTS.md` split.

**Lens:** production-readiness for the users we already have (~188 installs, plus
the meetup talk / Ruby Australia audience). Ordered by **user impact**, not by
effort. The guiding rule for a CI-and-cache tool: *it must never silently produce
a wrong answer.* A false "nothing changed" or a stale "cached" is worse than a
crash, because users trust the green checkmark.

Each item is self-contained enough to hand to Claude Code as a task: where it
lives, why it bites a real user, a fix sketch, and rough effort.

---

## P0 — Silent-wrong-answer (highest priority)

One open code bug (**P0.1**) and one investigated-and-closed-by-decision item
(**P0.2**, kept below with its reasoning). The guiding rule: a CI-and-cache tool
must never quietly report a wrong answer under conditions a normal user will hit.

### P0.1 — `affected` fails silently when the base ref is unreachable → false-green CI

> **✅ Done this pass.** Shipped as **1a** (validate the resolved base ref — auto-detected or explicit) + **1b** (a base-diff failure is fatal; working-tree-diff failures stay graceful). `InvalidBaseRefError` gained an optional `reason:`. Reproduced, fixed, and re-verified end-to-end; full suite green.

**Where:** `lib/rwm/affected_detector.rb` — `detect_changed_files`, `detect_base_branch`,
`validate_base_branch!`. Surfaces via `lib/rwm/commands/affected.rb` and the
`--affected` path in `lib/rwm/commands/run.rb`.

**Problem:** `detect_changed_files` runs `git diff --name-only <base>...HEAD` and only
keeps the output `if status.success?`. If the base ref isn't present locally — a
shallow CI clone, a fork PR, the documented `git fetch origin main` step missing or
its `if:` guard misfiring, a non-GitHub CI — the diff command fails, contributes
**zero** files, and the run reports `No packages affected` / `No affected packages.
Nothing to run.` and **exits 0**. CI goes green having tested nothing.

`validate_base_branch!` already exists but is only called for an **explicit** `--base`
(`validate_base_branch! if base_branch`). The auto-detected base is never validated,
and `detect_base_branch`'s last resort is to return `"main"` unconditionally even when
no such ref exists.

This directly undermines the headline use case ("CI that only tests what changed").
`docs/running-tasks.md:201` documents the `git fetch` precondition, but documenting a
precondition that fails *silently* when violated is the trap, not the fix.

**Heads-up — the silent-empty is partly *deliberate*.** `spec/rwm/affected_detector_spec.rb`
has a test "handles failed git diff commands gracefully" (≈ll. 383–407) that stubs the diff
commands to fail and asserts `affected_packages` is empty. So the fix is split:

**Fix 1a (non-breaking — closes the reproduced bug):** always validate the *resolved* base
ref, auto-detected or explicit (today `validate_base_branch! if base_branch` only guards the
explicit case). If the base commit doesn't exist, raise `Rwm::InvalidBaseRefError` with a
fetch hint. Leaves the "graceful diff failure" spec untouched — its fixture has a valid base
and only simulates a diff-command failure.

**Fix 1b (behaviour change — needs sign-off):** treat failure of the *base* diff
(`<base>...HEAD`) as a hard error too, distinct from staged/unstaged-diff failures. Catches
the shallow-clone-with-truncated-history case (base ref present, no merge-base). This rewrites
the "handles failed git diff commands gracefully" spec.

**Tests:** auto-detected base that doesn't exist → raises (new, currently red); explicit
`--base bogus` still raises (existing regression); for 1b, base-diff failure raises while a
clean repo with no changes still returns empty.

**Effort:** 1a ≈ 1 hour; 1b ≈ half a day with the spec rework.

---

### P0.2 — Cache hash omits Ruby version / lockfile — RESOLVED this pass (no code)

Investigated and reproduced (`/tmp/p02_repro.sh` for the gitignored-lockfile case,
`/tmp/p03_repro.sh` for `.ruby-version` placement), then closed by decision:

- **Gemfile.lock (external dep versions): no action.** RWM's cache key is "git-tracked files
  + workspace dep graph", consistent with its git-as-source-of-truth design. `rwm new` writes
  no `.gitignore`, and the canonical `rwm_test` workspace tracks every `Gemfile.lock`, so RWM
  never induces the gitignored-lockfile case. If a user deliberately gitignores their lockfile,
  RWM honours that rather than dictating; apps that commit the lockfile already get dep-change
  invalidation for free. Not a bug.
- **Ruby version: documented, not coded.** The interpreter version is never in the key (a
  *package-local* `.ruby-version` is hashed incidentally; a *root* one is not, and
  rbenv-global / asdf / CI-yaml pinning leave no hashed file at all). We documented the caveat
  + remedy (`rwm cache clean` after a Ruby upgrade) in `docs/running-tasks.md` rather than
  folding `RUBY_VERSION` into the digest. Revisit the code fix (B1) only if users report stale
  hits across a Ruby matrix.

---

## P1 — Robustness issues users hit in normal use

### P1.1 — SIGINT (Ctrl+C) orphans subprocesses

**Where:** `lib/rwm/task_runner.rb` — the `Signal.trap("INT")` block (~:49) and
`run_single`'s `Open3.capture3` (~:157).

**Problem:** the trap does `running.each_value { |t| t.kill }`. `Thread#kill` is a hard
kill of the **worker thread**, not the `rake`/Rails **child process** it spawned via
`Open3.capture3`. The child keeps running — orphaned, often holding a port or a DB
connection. Every interactive user Ctrl+Cs a slow run eventually; this is a routine path,
not an edge case.

**Fix:** track child PIDs alongside threads (switch `capture3` → `popen3` or `spawn` +
`Process.detach`). On interrupt: SIGTERM each child, wait briefly (~2s), SIGKILL stragglers,
then unwind threads. The existing `IOError` rescue stays for the in-flight-read case.

**Tests:** spawn a long-sleeping child task, send SIGINT, assert the runner exits within a
bounded time and no child PID survives.

**Effort:** ~1 day (architecture change to the runner's process model).

---

### P1.2 — Locale-fragile / version-fragile task-not-found detection

**Where:** `lib/rwm/task_runner.rb` — `NO_TASK_PATTERN` (~:17), used in `run_single`.

**Problem:** "task not found" is detected by regex-matching Rake's **English** error text
(`don't know how to build task`). Under a non-English `LANG`, or a future Rake that rewords
the message, a genuinely-missing task is classified as **failed** instead of **skipped** —
a false red across the workspace (e.g. `rwm lint` where only some packages define `lint`).

**Fix (two stages):**
1. **Quick mitigation, do now (one line):** force English on the subprocess by adding
   `"LC_ALL" => "C"` (and/or `"LANG" => "C"`) to the hash returned by `Rwm.bundle_env`
   (`lib/rwm.rb:25`). De-risks the locale half cheaply.
2. **Proper fix, later:** stop string-matching. Probe task existence directly — `bundle
   exec rake -T <task>` or a small `Rake::Task.task_defined?` invocation — cached per
   package per run, run in parallel with the rest of scheduling.

**Tests:** existing regex path; new probe path; non-English-locale behaviour.

**Effort:** mitigation ~10 min; proper fix ~half a day.

---

## P2 — DX & operability

### P2.1 — `rwm doctor`

**What:** a diagnostic command — "what's wrong with my setup" — printing `✓`/`✗` per check
with a summary and a 0/1 exit. The single highest-leverage onboarding/support reducer for a
growing install base.

**Should detect:** dep-graph cycles (currently only surface mid-command); packages missing
`Gemfile`/gemspec/`Rakefile`; packages not yet bootstrapped (no installed bundle); stale cache
entries for packages that no longer exist; `.ruby-version` skew across packages; `git`/`bundle`
present on PATH and their versions. Naturally absorbs much of P3.4 (cache stats).

**Effort:** ~1–2 days; can ship checks incrementally.

### P2.2 — Distinct exit codes per error class

**Where:** `lib/rwm/cli.rb` rescue block; classes already exist in `lib/rwm/errors.rb`.

**Problem:** the error hierarchy landed in 0.6.5, but the CLI still exits `1` for everything
(and `130` for Interrupt). Shell scripts can't distinguish "cycle" from "package not found"
from "base ref invalid."

**Fix:** map classes → stable exit codes (e.g. cycle=3, not-found=4, convention=5, base-ref=6).
Document them in `docs/command-reference.md`. Keep generic `Rwm::Error` → 1 as the default.

**Effort:** ~1 hour.

### P2.3 — `RWM_CACHE_DIR` (configurable cache location) — *low; mostly already solved*

The advertised CI flow already persists the cache by pointing `actions/cache` at the known
`.rwm/` path (`docs/running-tasks.md:171`), so this is no longer load-bearing. Only worth doing
if a user needs the cache **outside** the workspace tree (shared/read-only CI mount). Park until
asked.

---

## P3 — Features (scale / scripting) — lower urgency for the current user base

- **`--json` output** on `affected`, `list`, `info`, `graph`. For piping into CI/scripts.
  Add per-command schema specs.
- **`rwm graph --focus <pkg>` + `--depth N`** — render only a package's transitive deps and
  dependents. Easy given `transitive_dependencies` / `transitive_dependents`; filter before
  `to_dot`/`to_mermaid`. (Mostly a readability win at 50+ packages — few current users are there.)
- **`rwm run --bail` / `--until-fail`** — stop scheduling new packages on first failure for fast
  interactive feedback. Default stays "let in-flight finish, report all" for CI. Decide
  wait-vs-kill for in-flight (ties into P1.1's process model).
- **`rwm cache stats`** + optional per-run hit/miss summary — answers "caching doesn't seem to
  help." Largely subsumed by `rwm doctor`; do there or here, not both.

---

## P4 — Internal health / someday

- **Pre-compute path lookup** in `affected_detector.rb` (`map_files_to_packages`,
  `file_in_any_package?`) — currently O(files × packages). Only matters at ~200+ packages with
  large diffs; no current user is near that. Sorted-prefix `bsearch` or a path-trie when it
  becomes real.
- **`RakeCache` module-state → instantiable** (`lib/rwm/rake.rb`). The `reset!` helper is the
  tell that global state leaks between in-process runs. Works today because specs use
  subprocesses. "Noted, not urgent" — only touch if already in this file.

---

## Recently shipped (0.6.5) — done, kept here briefly for traceability

Cache: version salt (`CACHE_HASH_VERSION`), 64 KiB streaming digest, iterative
topological-order hashing (no `SystemStackError` on deep chains). Graph:
`to_json_data(workspace_root:)` kwarg, `@workspace_root` side-effect removed. Errors:
`InvalidBaseRefError`, `GemfileParseError`, `CacheError` added and raised at call sites.
Docs: SECURITY.md `eval_gemfile` trust-boundary note. Tests: diamond-graph parallel-start
spec hardened against CI jitter.

## Explicitly not now

Distribution/marketing polish (comparison table, asciinema/GIF, profile README) — the
"spread the word" side is in reasonable shape (talk on YouTube, Ruby Australia newsletter).
Focus is production-readiness for existing users, per the lens above.
