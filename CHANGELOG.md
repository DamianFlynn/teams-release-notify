# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.1.1

### Changed

- README: "Audit trail" section recommending `require-reference: true`, and `actions/checkout` pinned by SHA in the examples (#1)

## 1.1.0

### Added

- `require-reference` input on the changelog action: fails when a bullet has no PR reference or commit SHA (291f633)
- The release workflow refuses to overwrite an existing version tag or release, requires references in the changelog section, and verifies the release body contains the section verbatim (291f633)
- README documents the audit-evidence conventions: referenced bullets, verbatim release notes, immutable version tags (291f633)

## 1.0.0

Predates the reference convention; shipped in b0f5af3.

### Added

- `DamianFlynn/teams-release-notify` action: posts an Adaptive Card (heading, subtitle, facts, notes, buttons) to a Microsoft Teams Workflows webhook. Skips without a URL, masks the URL and only warns on failure unless `fail-on-error` is set.
- `DamianFlynn/teams-release-notify/changelog` action: extracts a version's (or date's) section from a changelog, with a `latest` mode.
- Tests, shellcheck and a live test card in CI, and a release workflow that publishes the tag, moves the major tag and announces itself.
