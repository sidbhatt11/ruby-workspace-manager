# TODO

## BUNDLE_GEMFILE inheritance in task runner

When `bin/rwm` runs as a binstub, the root Gemfile's `BUNDLE_GEMFILE` environment variable propagates to child processes spawned by the task runner. This means `bundle exec rake spec` in a package can resolve against the root Gemfile instead of the package's own Gemfile, causing "can't find executable rspec" errors when rspec isn't in the root bundle.

**Impact:** Any package whose Rakefile runs `bundle exec <tool>` (e.g., `sh "bundle exec rspec"`) can fail when invoked via `bin/rwm run` if the tool isn't in the root Gemfile.

**Fix:** Clear or reset `BUNDLE_GEMFILE` and related Bundler environment variables in `TaskRunner#run_single` before spawning the child process via `Open3.capture3`. Bundler will then resolve from the package's own Gemfile based on the `chdir:` directory.
