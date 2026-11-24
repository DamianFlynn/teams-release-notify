# teams-release-notify

Announce releases and content changes in a Microsoft Teams channel through a Teams Workflows webhook (template "Send webhook alerts to a channel"). Composite actions, bash + jq + curl only.

- No webhook URL: the step prints a notice and returns `skipped`. Forks without the secret keep working.
- The URL is masked, passed to curl on stdin and scrubbed from error text.
- A failed send is a warning, not a failed job, unless `fail-on-error: true`.

## Notify: `DamianFlynn/teams-release-notify@v1`

| Input | Required | Description |
|---|---|---|
| `webhook-url` | no | Webhook URL. Empty skips. |
| `heading` | yes | Card title (bold). |
| `subtitle` | no | Subtle line under the title. |
| `facts` | no | Lines of `Label \| value`, shown as a fact table. Values may hold markdown links. |
| `notes` | no | Markdown body. Cut at `max-notes-length` with a "see the release" note. |
| `changelog-path`, `changelog-version` | no | When `notes` is empty, use that version's changelog section. A missing section warns and still sends. |
| `links` | no | Lines of `Label \| URL`, shown as buttons. Max 6. |
| `max-notes-length` | no | Default `3000`. |
| `fail-on-error` | no | Default `false`. |

Output `result`: `sent`, `skipped` or `failed`.

## Changelog: `DamianFlynn/teams-release-notify/changelog@v1`

| Input | Default | Description |
|---|---|---|
| `path` | `CHANGELOG.md` | Changelog file. |
| `version` | (required) | Version or date. A leading `v` is ignored. `latest` returns the first section that is not `Unreleased`. |
| `required` | `true` | Fail when the section is missing or empty. |
| `require-reference` | `false` | Fail when a bullet in the section has no PR reference (`#123`) or commit SHA (7 to 40 hex characters, at least one digit). The offending bullets are listed in the error. |

Outputs: `found` (`true`/`false`), `notes` (section body), `version` (cleaned heading, handy with `latest`).

Matching headings: `## 1.2.3`, `## v1.2.3`, `## [1.2.3]`, `## [1.2.3] - 2026-11-24`, `## 1.2.3 (2026-11-24)` and date headings such as `## 2026-11-24`. The section runs to the next `## ` heading.

## Audit trail

- **Every changelog bullet references a PR or commit**, so each line can be traced to the change behind it:

  ```markdown
  ## 1.2.0

  ### Added

  - Support for custom card colours (#42)
  - Retry once on HTTP 429 (3f9a1c2)
  ```

  Enforce it with `require-reference: true` on the changelog action (recommended).
- **The release body is the changelog section, verbatim.** Create the release from the action's `notes` output and re-read the body afterwards to prove it.
- **Version tags are immutable.** Refuse to publish if the `vX.Y.Z` tag or release already exists; only the major alias (`v1`) moves. This repository's `release` workflow does all three and is a working reference.

## Example: release workflow

```yaml
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - id: cl
        uses: DamianFlynn/teams-release-notify/changelog@v1
        with:
          version: ${{ github.ref_name }}
          require-reference: 'true'   # every bullet cites a PR (#123) or commit SHA
      - name: Create the release from the changelog section and verify it
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ github.ref_name }}
          NOTES: ${{ steps.cl.outputs.notes }}
        run: |
          gh release create "$TAG" --title "$TAG" --notes "$NOTES"
          body="$(gh release view "$TAG" --json body -q .body | tr -d '\r')"
          [[ "$body" == *"$NOTES"* ]] || { echo "::error::Release body differs from the changelog"; exit 1; }
      - uses: DamianFlynn/teams-release-notify@v1
        with:
          webhook-url: ${{ secrets.TEAMS_RELEASES_WEBHOOK }}
          heading: ${{ github.event.repository.name }} ${{ github.ref_name }}
          subtitle: New release
          facts: |
            Version | ${{ github.ref_name }}
            Released by | ${{ github.actor }}
          notes: ${{ steps.cl.outputs.notes }}
          links: |
            View release | ${{ github.server_url }}/${{ github.repository }}/releases/tag/${{ github.ref_name }}
```

## Example: announce content changes on merge to main

The changelog uses date headings (`## 2026-11-24`) and each bullet cites its PR, e.g. `- Added the VPN runbook (#31)`; the card carries that day's section.

```yaml
on:
  push:
    branches: [main]
    paths: ['CHANGELOG.md']
jobs:
  announce:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - id: cl
        uses: DamianFlynn/teams-release-notify/changelog@v1
        with:
          version: latest
          required: false
      - if: steps.cl.outputs.found == 'true'
        uses: DamianFlynn/teams-release-notify@v1
        with:
          webhook-url: ${{ secrets.TEAMS_RELEASES_WEBHOOK }}
          heading: Content updated ${{ steps.cl.outputs.version }}
          notes: ${{ steps.cl.outputs.notes }}
          links: |
            Repository | ${{ github.server_url }}/${{ github.repository }}
```

## Development

```sh
shellcheck -S warning scripts/*.sh tests/run.sh
bash tests/run.sh
```

`TRN_DRY_RUN=1` makes `scripts/notify.sh` print the payload instead of sending it. Releases: add a `## x.y.z` section to `CHANGELOG.md` (every bullet with a PR or commit reference), then run the `release` workflow with the tag.

MIT licensed.
