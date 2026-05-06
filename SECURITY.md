# Security Policy

## Trust Model

RWM is a developer tool, not a sandbox. It assumes the workspace it operates on is code you already trust to run on your machine.

Specifically:

- **Gemfile parsing.** RWM reads each package's `Gemfile` via Bundler's DSL (`Bundler::Dsl#eval_gemfile`), which evaluates Gemfile contents as Ruby. Parsing a malicious Gemfile is arbitrary code execution.
- **Rake tasks.** `rwm run`, `rwm spec`, and `rwm bootstrap` shell out to `rake` and `bundle` in each package directory. Running `rake` against a malicious `Rakefile` is arbitrary code execution.
- **Path resolution.** `rwm` resolves the workspace root via `git rev-parse --show-toplevel` and reads files beneath it. Symlinks are followed.

This is the same trust posture as `bundle install` or `rake` itself — if you'd already run those in a directory, you can run `rwm` there.

**Do not run `rwm` in directories containing untrusted Gemfiles or Rakefiles** (for example, a fresh clone of an unfamiliar repository you haven't reviewed).

## Supported Versions

Until we reach 1.0, only the **latest** release receives security patches. There are no backports to older versions.

If you want security fixes as soon as they ship, leave the version unconstrained:

```ruby
gem "ruby_workspace_manager"
```

If you prefer stability and can tolerate a short delay before upgrading, pin to the current minor:

```ruby
gem "ruby_workspace_manager", "~> 0.6"
```

Everything can break between minor versions before 1.0. This policy will be revisited after 1.0.

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately via [GitHub Security Advisories](https://github.com/sidbhatt11/ruby-workspace-manager/security/advisories/new).

Do not open a public issue for security vulnerabilities.

You can expect an initial response within 72 hours. Once confirmed, a fix will be prioritized and released as a patch version.

## Gem Publishing

Releases are pushed to RubyGems manually by the maintainer with MFA enabled. This is intentional — there is no CI/CD path to RubyGems, so a compromised pipeline cannot publish a malicious release.
