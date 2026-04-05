[← Back to README](../README.md)

# Rails and Zeitwerk

## How workspace libs work in Rails

Workspace libs declared via `rwm_lib` are path gems. The standard Rails boot sequence handles them automatically:

1. `config/boot.rb` calls `Bundler.setup` — adds all gem `lib/` directories to `$LOAD_PATH`
2. `config/application.rb` calls `Bundler.require(*Rails.groups)` — auto-requires every gem, including workspace libs and their transitive deps
3. `config/environment.rb` calls `Rails.application.initialize!` — Zeitwerk activates for the app's own code

By the time Zeitwerk starts in step 3, workspace libs are already loaded as plain Ruby modules. Zeitwerk never touches them — it only manages directories in `config.autoload_paths`.

**No special setup is needed in `application.rb`.** A standard Rails template works:

```ruby
# apps/web/Gemfile
require "rwm/gemfile"

source "https://rubygems.org"
gemspec

rwm_lib "auth"    # transitive deps resolved automatically
```

```ruby
# apps/web/config/application.rb
require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    config.load_defaults 8.0
  end
end
```

That's it. `Bundler.require` loads `auth` and all of its transitive workspace dependencies. No manual `Rwm.require_libs`, no ordering tricks.

## A note on Zeitwerk

Zeitwerk uses `Module#autoload` and `const_missing` to lazily load files from `config.autoload_paths`. It does **not** override `Kernel#require`. A plain `require "auth"` (from `Bundler.require` or anywhere else) works normally at any point during the boot sequence — Zeitwerk does not intercept it. This is why workspace libs loaded by `Bundler.require` coexist peacefully with Zeitwerk.

## The practical lib workflow

**Develop inside your Rails app first.** While a feature is in active development, keep the code in your Rails app's `app/` directory where Zeitwerk gives you hot reloading for free. Change a file, refresh the page, see the result.

**Extract when stable.** When the code has solidified — the interface is settled, multiple apps could use it, you're not changing it every day — extract it into a workspace lib. This is the natural monorepo rhythm: apps are where you experiment, libs are where you consolidate.

At extraction time, choose how the lib is structured.

## Traditional structure (the default)

This is what `rwm new lib` scaffolds. The lib's entry point loads all sub-files eagerly with `require_relative`:

```ruby
# libs/auth/lib/auth.rb
require_relative "auth/token"
require_relative "auth/user"

module Auth
  VERSION = "0.1.0"
end
```

**Pros:** Works everywhere — Rails, non-Rails, any Ruby app. Simple. Standard gem structure.

**Cons:** No hot reloading in Rails development. After changing a lib file, you restart the server. This is fine for stable extracted code — you're not changing it often.

This is the right choice for most workspace libs.

## Zeitwerk-compatible structure (opt-in)

Choose this when you're still actively iterating on a lib **and** multiple Rails apps consume it. The lib follows Zeitwerk naming conventions — one constant per file, no `require_relative`:

```ruby
# libs/auth/lib/auth.rb
module Auth
end

# libs/auth/lib/auth/token.rb — defines Auth::Token
# libs/auth/lib/auth/user.rb  — defines Auth::User
# Zeitwerk auto-discovers these. No require lines needed.
```

Each consuming Rails app opts in by adding the lib to its autoload paths and telling Bundler not to auto-require it. `Rwm.lib_path("auth")` returns the absolute path to `libs/auth/lib` — it's available after `require "rwm/rails"`:

```ruby
# apps/web/Gemfile
rwm_lib "auth", require: false    # Bundler won't auto-require
```

```ruby
# apps/web/config/application.rb
require "rwm/rails"

module Web
  class Application < Rails::Application
    config.autoload_paths << Rwm.lib_path("auth")
    config.eager_load_paths << Rwm.lib_path("auth")
  end
end
```

Now Zeitwerk manages `auth` — lazy loading in development (with hot reloading), eager loading in production. Changes to lib files are picked up on the next request without restarting the server.

**Trade-offs:**

- All consumer apps must add the lib to their autoload paths — this is a per-app decision
- The lib cannot use `require_relative` for its own files (Zeitwerk must control loading)
- Non-Rails consumers need a different loading strategy (e.g., `Zeitwerk::Loader.for_gem` or a `Dir.glob` require)

## What doesn't work

**Mixing `Bundler.require` and `autoload_paths` for the same lib.** If `Bundler.require` loads a lib (the default) and you also add it to `config.autoload_paths`, the lib's constants are loaded twice — once eagerly by Bundler, once lazily by Zeitwerk. Reloading breaks because Zeitwerk didn't control the initial load. Pick one or the other per lib.

**Using `require_relative` inside a Zeitwerk-managed lib.** Initial loading works fine — Zeitwerk tolerates other loading mechanisms. But after a Zeitwerk reload cycle (in development), files loaded by `require_relative` are still in `$LOADED_FEATURES`. Ruby's `require_relative` sees them as already loaded and skips them. The constants were removed by Zeitwerk's reload but never re-defined. Result: `NameError`.

## `Rwm.require_libs` — when you need it

For standard Rails apps, `Bundler.require` handles everything. `Rwm.require_libs` exists for edge cases:

- Non-standard Rails setups that don't call `Bundler.require`
- Non-Rails apps that want to load all workspace libs in one call
- Explicit control over when workspace libs are loaded

```ruby
require "rwm/rails"
Rwm.require_libs    # requires all libs resolved by rwm_lib, idempotent
```

Non-Rails apps don't need any of this — `require` workspace libs from your Gemfile anywhere in your code, as with any gem.
