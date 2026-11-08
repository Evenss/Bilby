# Security policy

## Scope

Security fixes target the latest project revision on macOS 27.2 / Apple Silicon.
Older revisions and other operating systems do not have a support commitment.

Bilby reads menu bar metadata through Accessibility and uses a private macOS
visibility API. It does not require screen recording access, synthesize input,
or perform accessibility actions in other applications.

## Reporting a vulnerability

Use [GitHub's private vulnerability reporting form](https://github.com/Evenss/Bilby/security/advisories/new).
Do not include exploit details in a public issue.

Include the affected revision, macOS version and build, reproduction steps,
expected impact, and a minimal proof of concept when available. Remove unrelated
personal data from logs and captures. Coordinate public disclosure with the
maintainer through the private report.

Ordinary visibility, layout, and compatibility bugs belong in
[Issues](https://github.com/Evenss/Bilby/issues).
