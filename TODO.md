# RWM — TODO

Working backlog of pending technical work for `ruby-workspace-manager`, ordered by
**user impact**, not effort. Guiding rule for a CI-and-cache tool: *it must never
silently produce a wrong answer* — a false "nothing changed" or a stale "cached" is
worse than a crash, because users trust the green checkmark.

Each item is self-contained: where it lives, why it bites a user, a fix sketch, and
rough effort.

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
1. **Quick mitigation (one line):** force English on the subprocess by adding
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
with a summary and a 0/1 exit. High-leverage: the answer to "why isn't my workspace
behaving" without a support round-trip.

**Should detect:** dep-graph cycles (currently only surface mid-command); packages missing
`Gemfile`/gemspec/`Rakefile`; packages not yet bootstrapped (no installed bundle); stale cache
entries for packages that no longer exist; `.ruby-version` skew across packages; `git`/`bundle`
present on PATH and their versions. Naturally absorbs the cache-stats idea in P3.

**Effort:** ~1–2 days; can ship checks incrementally.

### P2.2 — Distinct exit codes per error class

**Where:** `lib/rwm/cli.rb` rescue block; classes already exist in `lib/rwm/errors.rb`.

**Problem:** the error hierarchy exists, but the CLI still exits `1` for everything
(and `130` for Interrupt). Shell scripts can't distinguish "cycle" from "package not found"
from "base ref invalid."

**Fix:** map classes → stable exit codes (e.g. cycle=3, not-found=4, convention=5, base-ref=6).
Document them in `docs/command-reference.md`. Keep generic `Rwm::Error` → 1 as the default.

**Effort:** ~1 hour.

---

## P3 — Features (scale / scripting) — lower urgency

- **`--json` output** on `affected`, `list`, `info`, `graph`. For piping into CI/scripts.
  Add per-command schema specs.
- **`rwm graph --focus <pkg>` + `--depth N`** — render only a package's transitive deps and
  dependents. Easy given `transitive_dependencies` / `transitive_dependents`; filter before
  `to_dot`/`to_mermaid`. Mainly a readability win at 50+ packages.
- **`rwm run --bail` / `--until-fail`** — stop scheduling new packages on first failure for fast
  interactive feedback. Default stays "let in-flight finish, report all" for CI. Decide
  wait-vs-kill for in-flight (ties into P1.1's process model).
- **`rwm cache stats`** + optional per-run hit/miss summary — surfaces the cache hit rate when
  someone suspects caching isn't helping. Largely subsumed by `rwm doctor`; do there or here,
  not both.

---

## P4 — Internal health / someday

- **Pre-compute path lookup** in `affected_detector.rb` (`map_files_to_packages`,
  `file_in_any_package?`) — currently O(files × packages). Matters mainly at ~200+ packages with
  large diffs. Sorted-prefix `bsearch` or a path-trie when it becomes real.
- **`RakeCache` module-state → instantiable** (`lib/rwm/rake.rb`). The `reset!` helper is the
  tell that global state leaks between in-process runs. Works today because specs use
  subprocesses. "Noted, not urgent" — only touch if already in this file.
