# AI-Assisted Development Workflow

This document describes how this project is developed using AI-assisted pair programming (Claude Code). It serves as a reference for maintainers, contributors, reviewers, and auditors who want to understand the process.

## Philosophy

The human is the architect. The AI is the builder. The human decides *what* to build and *why*. The AI handles *how* — writing code, running tests, managing git — but every meaningful decision is made or approved by the human.

AI-generated code is held to the same standard as human-written code. It goes through the same tests, the same review, and the same CI pipeline. The commit history attributes AI contributions via `Co-Authored-By` trailers.

## Roles

**Human (maintainer):**
- Sets direction, priorities, and constraints
- Reviews all code and documentation changes
- Makes architectural decisions (these are non-negotiable once made)
- Catches inconsistencies, unclear wording, and edge cases
- Approves releases

**AI (Claude Code):**
- Writes implementation code and tests
- Runs the test suite and fixes failures
- Manages git operations (commits, tags, pushes)
- Drafts documentation and changelogs
- Proofreads and identifies issues
- Provides technical analysis and trade-off assessments

## Workflow stages

### 1. Planning

Large changes start with a plan. The process varies by scope:

**Small changes** (typos, one-line fixes, doc tweaks): No plan needed. The human describes the change, the AI implements it directly.

**Medium changes** (new flag, bug fix, refactor): Brief discussion. The human describes the goal, the AI may ask clarifying questions or propose an approach, then implements.

**Large changes** (new commands, architectural changes, multi-file refactors): A written plan is created first, either in Claude Code's plan mode or as a `TODO.md` file. The plan includes:
- What files will be changed and how
- What tests will be added
- What the verification steps are

The plan is reviewed and approved by the human before implementation begins. Plans are temporary artifacts — they are deleted after the work is complete.

**Feature exploration** (future work, not yet committed to): Ideas are captured in `TO_PLAN.md` with investigation questions and goals. These are picked up in future sessions.

### 2. Implementation

Changes are implemented incrementally:

- **One logical change per commit.** A bug fix is one commit. A new feature with tests is one commit. Documentation for that feature may be a separate commit.
- **Tests are written alongside code.** No implementation is considered complete without tests. The AI writes tests as part of the same change, not as a follow-up.
- **The full test suite runs before every push.** Not just the tests for the changed files — the entire `bundle exec rspec` suite. This catches regressions.
- **Commits happen frequently.** After each logical piece of work is done and tests pass, it's committed and pushed. This keeps the history granular and makes it easy to bisect or revert.

### 3. Review

Review happens conversationally during development, not as a separate stage:

- The human reads the AI's output (code, docs, test results) as it's produced
- The human flags issues immediately: "this sentence is misleading", "use spec not test here", "that flag order is wrong"
- The AI fixes and re-commits
- For documentation, the human often does a final read-through and catches inconsistencies that the AI missed

This is more like pair programming than a PR review. The feedback loop is tight — usually seconds between "that's wrong" and the fix being committed.

### 4. Testing

The test suite is the source of truth for correctness:

- **Every feature has tests.** New commands, new flags, new behavior — all tested.
- **Edge cases are tested.** Empty inputs, missing files, concurrent access, error paths.
- **Tests run in random order** (`--order rand`) to catch hidden dependencies between tests.
- **The full suite must pass before any push.** No exceptions. If a test fails, it's fixed before moving on.
- **Coverage is monitored** but not gated. We aim for high coverage (~90%+) but don't block on a specific number.

### 5. Documentation

Documentation is treated as a first-class deliverable:

- **README is the primary document.** It's comprehensive and kept in sync with the code. There is no separate guide or wiki — everything lives in the README.
- **The CHANGELOG follows [Keep a Changelog](https://keepachangelog.com/) format.** Every release has a detailed entry with Added/Changed/Fixed sections.
- **Code changes that affect user-facing behavior update the README in the same session.** Not "we'll document it later" — it happens immediately.
- **The human proofreads documentation carefully.** The AI is good at generating comprehensive docs but can miss inconsistencies (e.g., using `rwm test` in examples when the default scaffold creates `spec`). The human catches these.

### 6. Releases

The release process:

1. Version bump in `lib/rwm/version.rb`
2. CHANGELOG.md updated with all changes since the last release
3. Full test suite passes
4. Commit and push
5. Git tag created and pushed
6. Gem built with `gem build`
7. GitHub release created with release notes and the `.gem` file attached
8. Human pushes to RubyGems manually (not automated — intentional)

The AI handles steps 1-7. The human handles step 8. This keeps the human in control of what gets published to the public registry.

## Conventions

### Git

- All commits include `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>` (or the model version used)
- Commits use `--no-gpg-sign`
- Commit messages are concise: imperative subject line, optional body explaining *why*
- Related commits may be squashed if the history is noisy (e.g., 9 iterative README edits → 1 clean commit)
- Force pushes to main are avoided unless explicitly requested for squashing

### Code style

- Follow existing patterns in the codebase. Don't introduce new conventions without discussion.
- No over-engineering. Only build what's needed now.
- No speculative abstractions. Three similar lines is better than a premature helper.
- Tests use the same patterns as existing tests. New test files follow the existing spec structure.

### Decision making

Some decisions are non-negotiable once made by the human. Examples from this project:
- Convention over configuration (no `.rwm.yml`)
- `libs/` and `apps/` directory structure
- No `rwm_app` helper (apps are leaf nodes)
- Zero runtime dependencies

The AI respects these constraints and does not re-propose alternatives unless explicitly asked for a fresh perspective.

## How to read the commit history

Every commit authored with the `Co-Authored-By` trailer was produced in an AI-assisted session. The human reviewed and approved each change before it was committed. The commit message describes what changed; the conversation that led to it is not preserved in the repo.

Commits without the trailer were made by the human independently.

## Tools

- **Claude Code** (CLI) — the AI pair programming tool used for all AI-assisted work
- **RSpec** — test framework
- **GitHub Actions** — CI pipeline
- **GitHub CLI (`gh`)** — release management
