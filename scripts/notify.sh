#!/usr/bin/env bash
# Post an Adaptive Card to a Teams Workflows webhook. Configured through TRN_* env vars:
#   TRN_WEBHOOK_URL TRN_HEADING TRN_SUBTITLE TRN_FACTS TRN_NOTES TRN_MAX_NOTES
#   TRN_CHANGELOG_PATH TRN_CHANGELOG_VERSION TRN_LINKS TRN_FAIL_ON_ERROR
#   TRN_DRY_RUN=1 prints the payload instead of sending it.
# Writes result=sent|skipped|failed to $GITHUB_OUTPUT. Never prints the webhook URL.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
url="${TRN_WEBHOOK_URL:-}"
fail_on_error="${TRN_FAIL_ON_ERROR:-false}"

emit() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "result=$1" >> "$GITHUB_OUTPUT"; return 0; }

scrub() {
  local s="$1"
  [ -n "$url" ] && s="${s//"$url"/***}"
  printf '%s' "$s"
}

fail() {
  local msg
  msg="$(scrub "$1")"
  emit failed
  if [ "$fail_on_error" = true ]; then
    echo "::error::Teams notification failed: $msg"
    exit 1
  fi
  echo "::warning::Teams notification failed and was ignored: $msg"
  exit 0
}

# Strip whitespace-only input.
case "$url" in
  *[![:space:]]*) ;;
  *) echo "::notice::No Teams webhook configured, skipping."; emit skipped; exit 0 ;;
esac
echo "::add-mask::$url"

heading="${TRN_HEADING:-}"
[ -n "$heading" ] || fail "the 'heading' input is required"

notes="${TRN_NOTES:-}"
case "$notes" in *[![:space:]]*) ;; *) notes="" ;; esac
if [ -z "$notes" ] && [ -n "${TRN_CHANGELOG_PATH:-}" ] && [ -n "${TRN_CHANGELOG_VERSION:-}" ]; then
  if ! notes="$("$here/changelog-section.sh" "$TRN_CHANGELOG_PATH" "$TRN_CHANGELOG_VERSION" body 2>/dev/null)"; then
    echo "::warning::No changelog section for '$TRN_CHANGELOG_VERSION' in $TRN_CHANGELOG_PATH, sending without notes."
    notes=""
  fi
fi

max="${TRN_MAX_NOTES:-3000}"
case "$max" in ''|*[!0-9]*) max=3000 ;; esac

facts="${TRN_FACTS:-}"; links="${TRN_LINKS:-}"
# Warn about malformed lines (the jq filter skips them).
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac
  case "$line" in *'|'*) ;; *) echo "::warning::Ignoring facts line without ' | ': $line" ;; esac
done <<< "$facts"
nlinks=0
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac
  case "$line" in
    *'|'*https://*|*'|'*http://*)
      nlinks=$((nlinks + 1))
      [ "$nlinks" -gt 6 ] && echo "::warning::More than 6 links, ignoring: $line" ;;
    *) echo "::warning::Ignoring links line without 'Label | http(s)://URL': $line" ;;
  esac
done <<< "$links"

# shellcheck disable=SC2016
filter='
def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
def pairs($s):
  $s | split("\n") | map(rtrimstr("\r") | trim) | map(select(length > 0 and contains("|")))
  | map((index("|")) as $i | {a: (.[:$i] | trim), b: (.[$i + 1:] | trim)})
  | map(select(.a != "" and .b != ""));
(($notes | trim)) as $n
| (if ($n | length) > $max then ($n[:$max] | sub("\\s+$"; "")) + "\n\n…see the release for the full notes." else $n end) as $notes_t
| ([{type: "TextBlock", text: $heading, weight: "Bolder", size: "Medium", wrap: true}]
   + (if ($subtitle | trim) != "" then [{type: "TextBlock", text: ($subtitle | trim), isSubtle: true, spacing: "None", wrap: true}] else [] end)
   + (pairs($facts) as $f | if ($f | length) > 0 then [{type: "FactSet", facts: ($f | map({title: .a, value: .b}))}] else [] end)
   + (if $notes_t != "" then [{type: "TextBlock", text: $notes_t, wrap: true}] else [] end)) as $body
| (pairs($links) | map(select(.b | test("^https?://"))) | .[:6] | map({type: "Action.OpenUrl", title: .a, url: .b})) as $actions
| {type: "message", attachments: [{contentType: "application/vnd.microsoft.card.adaptive", contentUrl: null,
    content: {"$schema": "http://adaptivecards.io/schemas/adaptive-card.json", type: "AdaptiveCard", version: "1.4",
              body: $body, actions: $actions}}]}'

payload="$(jq -n --arg heading "$heading" --arg subtitle "${TRN_SUBTITLE:-}" --arg facts "$facts" \
  --arg links "$links" --arg notes "$notes" --argjson max "$max" "$filter" 2>&1)" \
  || fail "could not build the card: $payload"

if [ "${TRN_DRY_RUN:-}" = 1 ]; then
  printf '%s\n' "$payload"
  emit sent
  exit 0
fi

# The URL is passed on stdin (curl config) so it never appears in the process list.
resp="$(printf 'url = "%s"\n' "$url" | curl -sS --fail-with-body --max-time 30 -K - \
  -X POST -H 'Content-Type: application/json; charset=utf-8' --data-binary "$payload" 2>&1)" \
  || fail "$resp"

echo "Teams notification sent."
emit sent
