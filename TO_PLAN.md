# To Plan

Items to investigate and plan before implementing.

## 1. Lower the Ruby version floor

Currently requires Ruby >= 3.4.0. This cuts off a large chunk of potential users — many production Ruby shops are on 3.1, 3.2, or 3.3 and don't upgrade quickly.

**What to investigate:**
- Audit the codebase for 3.4-specific syntax or APIs (e.g., `it` as block parameter, pattern matching refinements, `frozen_string_literal` behavior changes)
- Check if any gem dependencies or stdlib features we use were introduced in 3.4
- Determine the lowest Ruby version we can reasonably support without rewriting significant code
- Run the test suite against 3.1, 3.2, and 3.3 to see what breaks
- Update CI matrix to test against all supported versions

**Goal:** Support Ruby >= 3.1 (or the lowest feasible version) to maximize adoption. 3.1 is still in maintenance, 3.2+ is actively supported.

## 2. Railtie for automatic Zeitwerk integration

Currently, Rails users must manually edit `config/application.rb` to add `require "rwm/rails"` and `Rwm.require_libs` before `require "rails"`. This is documented but easy to get wrong — the ordering is fragile and the failure mode (Zeitwerk `LoadError`) is confusing.

**What to investigate:**
- Can a Railtie's `before_configuration` or `before_initialize` hook run early enough (before Zeitwerk activates) to require workspace libs?
- If not, can we use a Bundler plugin or `require` hook that fires during `Bundler.setup`?
- Look at how other gems solve the "must load before Zeitwerk" problem
- Determine if we can detect workspace libs automatically from `Rwm.resolved_libs` without any user code in `application.rb`
- Consider backwards compatibility — the manual approach should still work for users who prefer explicit control

**Goal:** `gem "ruby_workspace_manager"` in the Gemfile is all a Rails app needs. No manual `application.rb` edits. Workspace libs are required automatically at the right point in the boot sequence.
