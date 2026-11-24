# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.0.0

### Added

- `DamianFlynn/teams-release-notify` action: posts an Adaptive Card (heading, subtitle, facts, notes, buttons) to a Microsoft Teams Workflows webhook. Skips without a URL, masks the URL and only warns on failure unless `fail-on-error` is set.
- `DamianFlynn/teams-release-notify/changelog` action: extracts a version's (or date's) section from a changelog, with a `latest` mode.
- Tests, shellcheck and a live test card in CI, and a release workflow that publishes the tag, moves the major tag and announces itself.
