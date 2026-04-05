# Security Policy

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
