#!/usr/bin/env bash
# Test suite for the notify and changelog scripts. Works with bash 3.2+.
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; [ -n "${srv:-}" ] && kill "$srv" 2>/dev/null' EXIT
pass=0; failn=0
ok()  { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { failn=$((failn + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && echo "       $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

FAKE='https://example.invalid/secret/webhook-TOKEN123'
notify() { env -i PATH="$PATH" TRN_DRY_RUN=1 TRN_WEBHOOK_URL="$FAKE" "$@" bash "$root/scripts/notify.sh"; }

# ---- payload shape
out="$(notify TRN_HEADING='Release 1.0' TRN_SUBTITLE='sub' TRN_FACTS=$'Version | 1.0\n\nRepo | [r](https://x.io)\nbad line' \
  TRN_NOTES='Some *notes*' TRN_LINKS=$'View | https://x.io/r\nBad | nope' 2>&1)"
json="$(printf '%s\n' "$out" | grep -v '^::')"
eq "type message" "$(jq -r .type <<<"$json")" message
eq "contentType" "$(jq -r '.attachments[0].contentType' <<<"$json")" application/vnd.microsoft.card.adaptive
eq "contentUrl null" "$(jq -r '.attachments[0].contentUrl' <<<"$json")" null
eq "card version" "$(jq -r '.attachments[0].content.version' <<<"$json")" 1.4
eq "schema" "$(jq -r '.attachments[0].content["$schema"]' <<<"$json")" http://adaptivecards.io/schemas/adaptive-card.json
eq "heading block" "$(jq -r '.attachments[0].content.body[0] | "\(.text)|\(.weight)|\(.size)"' <<<"$json")" 'Release 1.0|Bolder|Medium'
eq "subtitle subtle" "$(jq -r '.attachments[0].content.body[1].isSubtle' <<<"$json")" true
eq "facts count (blank + malformed ignored)" "$(jq '.attachments[0].content.body[2].facts | length' <<<"$json")" 2
eq "fact value with link" "$(jq -r '.attachments[0].content.body[2].facts[1].value' <<<"$json")" '[r](https://x.io)'
eq "notes block" "$(jq -r '.attachments[0].content.body[3].text' <<<"$json")" 'Some *notes*'
eq "links count (bad ignored)" "$(jq '.attachments[0].content.actions | length' <<<"$json")" 1
eq "link action" "$(jq -r '.attachments[0].content.actions[0] | "\(.type)|\(.title)|\(.url)"' <<<"$json")" 'Action.OpenUrl|View|https://x.io/r'
case "$out" in *'Ignoring facts line'*) ok "malformed fact warned" ;; *) bad "malformed fact warned" ;; esac
case "$out" in *'Ignoring links line'*) ok "malformed link warned" ;; *) bad "malformed link warned" ;; esac

# ---- special characters survive JSON building
json="$(notify TRN_HEADING='He said "hi" \ back' TRN_NOTES=$'line1\nline2 "q"' | grep -v '^::')"
eq "quotes in heading" "$(jq -r '.attachments[0].content.body[0].text' <<<"$json")" 'He said "hi" \ back'
eq "newlines in notes" "$(jq -r '.attachments[0].content.body[1].text' <<<"$json" | wc -l | tr -d ' ')" 2

# ---- minimal card: no optional blocks
json="$(notify TRN_HEADING=H | grep -v '^::')"
eq "minimal body is one block" "$(jq '.attachments[0].content.body | length' <<<"$json")" 1
eq "minimal actions empty" "$(jq '.attachments[0].content.actions | length' <<<"$json")" 0

# ---- truncation
long="$(printf 'a%.0s' $(seq 1 50))"
json="$(notify TRN_HEADING=H TRN_NOTES="$long" TRN_MAX_NOTES=10 | grep -v '^::')"
eq "notes truncated" "$(jq -r '.attachments[0].content.body[1].text' <<<"$json")" "$(printf 'aaaaaaaaaa\n\n…see the release for the full notes.')"
json="$(notify TRN_HEADING=H TRN_NOTES="$long" | grep -v '^::')"
eq "notes under default limit untouched" "$(jq -r '.attachments[0].content.body[1].text' <<<"$json")" "$long"

# ---- max 6 links
links=""; for i in 1 2 3 4 5 6 7 8; do links="${links}L$i | https://x.io/$i"$'\n'; done
out="$(notify TRN_HEADING=H TRN_LINKS="$links" 2>&1)"
eq "links capped at 6" "$(printf '%s\n' "$out" | grep -v '^::' | jq '.attachments[0].content.actions | length')" 6
case "$out" in *'More than 6 links'*) ok "extra links warned" ;; *) bad "extra links warned" ;; esac

# ---- notes from changelog
printf '# Changelog\n\n## 2.0.0\n\n- two\n\n## 1.0.0\n\n- one\n' > "$tmp/CL.md"
json="$(notify TRN_HEADING=H TRN_CHANGELOG_PATH="$tmp/CL.md" TRN_CHANGELOG_VERSION=v2.0.0 | grep -v '^::')"
eq "notes from changelog" "$(jq -r '.attachments[0].content.body[1].text' <<<"$json")" '- two'
out="$(notify TRN_HEADING=H TRN_CHANGELOG_PATH="$tmp/CL.md" TRN_CHANGELOG_VERSION=9.9.9 2>&1)"
case "$out" in *'::warning::No changelog section'*) ok "missing changelog section warns" ;; *) bad "missing changelog section warns" ;; esac
eq "missing section still sends" "$(printf '%s\n' "$out" | grep -v '^::' | jq '.attachments[0].content.body | length')" 1
json="$(notify TRN_HEADING=H TRN_NOTES=explicit TRN_CHANGELOG_PATH="$tmp/CL.md" TRN_CHANGELOG_VERSION=2.0.0 | grep -v '^::')"
eq "explicit notes win over changelog" "$(jq -r '.attachments[0].content.body[1].text' <<<"$json")" explicit

# ---- skip without URL
: > "$tmp/out"
out="$(env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" TRN_HEADING=H bash "$root/scripts/notify.sh" 2>&1)"; rc=$?
eq "skip exit 0" "$rc" 0
case "$out" in *'::notice::No Teams webhook configured, skipping.'*) ok "skip notice" ;; *) bad "skip notice" "$out" ;; esac
eq "skip result" "$(cat "$tmp/out")" result=skipped
: > "$tmp/out"
env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" TRN_WEBHOOK_URL='   ' TRN_HEADING=H bash "$root/scripts/notify.sh" >/dev/null 2>&1
eq "whitespace url skips" "$(cat "$tmp/out")" result=skipped

# ---- URL masked, never printed
out="$(notify TRN_HEADING=H 2>&1)"
case "$out" in *'::add-mask::'"$FAKE"*) ok "url masked" ;; *) bad "url masked" ;; esac
printf '%s\n' "$out" | grep -v '^::add-mask::' | grep -q 'TOKEN123' && bad "url not printed elsewhere" || ok "url not printed elsewhere"

# ---- failure path never fails the step, never leaks the URL
bad_url='http://127.0.0.1:1/hook/SECRETPART'
: > "$tmp/out"
out="$(env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" TRN_WEBHOOK_URL="$bad_url" TRN_HEADING=H bash "$root/scripts/notify.sh" 2>&1)"; rc=$?
eq "failure exit 0" "$rc" 0
eq "failure result" "$(cat "$tmp/out")" result=failed
case "$out" in *'::warning::Teams notification failed'*) ok "failure warns" ;; *) bad "failure warns" "$out" ;; esac
printf '%s\n' "$out" | grep -v '^::add-mask::' | grep -q 'SECRETPART' && bad "failure does not leak url" "$out" || ok "failure does not leak url"
env -i PATH="$PATH" TRN_WEBHOOK_URL="$bad_url" TRN_HEADING=H TRN_FAIL_ON_ERROR=true bash "$root/scripts/notify.sh" >/dev/null 2>&1
eq "fail-on-error exits 1" "$?" 1
: > "$tmp/out"
env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" TRN_WEBHOOK_URL="$FAKE" bash "$root/scripts/notify.sh" >/dev/null 2>&1
eq "missing heading is a soft failure" "$(cat "$tmp/out")" result=failed

# ---- real POST against a local server (202 like Teams)
if command -v python3 >/dev/null 2>&1; then
  python3 - "$tmp" <<'PY' &
import http.server, sys
tmp = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        open(tmp + '/received.json', 'wb').write(body)
        open(tmp + '/ctype', 'w').write(self.headers.get('Content-Type', ''))
        self.send_response(202); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
open(tmp + '/port', 'w').write(str(s.server_port))
s.serve_forever()
PY
  srv=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$tmp/port" ] && break; sleep 0.3; done
  : > "$tmp/out"
  env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" TRN_WEBHOOK_URL="http://127.0.0.1:$(cat "$tmp/port")/h" TRN_HEADING=Live bash "$root/scripts/notify.sh" >/dev/null 2>&1
  eq "real POST result" "$(cat "$tmp/out")" result=sent
  eq "real POST body" "$(jq -r '.attachments[0].content.body[0].text' "$tmp/received.json")" Live
  eq "real POST content type" "$(cat "$tmp/ctype")" 'application/json; charset=utf-8'
else
  echo "skip - python3 not available, real POST test skipped"
fi

# ---- changelog parsing
sec() { "$root/scripts/changelog-section.sh" "$1" "$2" "${3:-body}"; }
mk() { printf '%s\n' "$2" > "$tmp/$1.md"; }
body=$'\nthe body\n- item\n\n'
for h in '## 1.2.3' '## v1.2.3' '## [1.2.3]' '## [1.2.3] - 2026-11-24' '## 1.2.3 (2026-11-24)' '## [v1.2.3] - 2026-11-24'; do
  mk v "# Changelog
${h}
${body}
## 1.2.2

old"
  r="$(sec "$tmp/v.md" 1.2.3)"; rc=$?
  eq "heading '$h' body" "$r" $'the body\n- item'
  eq "heading '$h' rc" "$rc" 0
  eq "heading '$h' with v input" "$(sec "$tmp/v.md" v1.2.3)" $'the body\n- item'
done
mk d "## 2026-11-24

- today

## 2026-11-20

- earlier"
eq "date section" "$(sec "$tmp/d.md" 2026-11-24)" '- today'
eq "date section older" "$(sec "$tmp/d.md" 2026-11-20)" '- earlier'
mk p "## 1.2.30

wrong

## 1.2.3

right

### Fixed

- sub heading kept"
eq "no prefix match, subheadings kept" "$(sec "$tmp/p.md" 1.2.3)" $'right\n\n### Fixed\n\n- sub heading kept'
mk c "## 1.0.0

crlf body" ; sed -i.bak 's/$/\r/' "$tmp/c.md"
eq "CRLF handled" "$(sec "$tmp/c.md" 1.0.0)" 'crlf body'
mk e "## 1.0.0

## 0.9.0

x"
r="$(sec "$tmp/e.md" 1.0.0)"; eq "empty section found but empty" "$r" ""
sec "$tmp/p.md" 4.4.4 >/dev/null 2>&1; eq "missing section rc 3" "$?" 3
sec "$tmp/nope.md" 1 >/dev/null 2>&1; eq "missing file rc 2" "$?" 2

# ---- latest mode
mk l "# Changelog

## [Unreleased]

- wip

## [3.1.0] - 2026-11-24

- newest

## [3.0.0]

- older"
eq "latest body skips Unreleased" "$(sec "$tmp/l.md" latest)" '- newest'
eq "latest heading cleaned" "$(sec "$tmp/l.md" latest heading)" 3.1.0
mk l2 "## v2.0.0 (2026-01-01)

- x"
eq "latest heading keeps v, drops date" "$(sec "$tmp/l2.md" latest heading)" v2.0.0

# ---- changelog action entry point
act() { env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/gh" CL_PATH="$1" CL_VERSION="$2" CL_REQUIRED="$3" bash "$root/scripts/changelog-action.sh" 2>&1; }
: > "$tmp/gh"; out="$(act "$tmp/v.md" 1.2.2 true)"; rc=$?
eq "action found rc" "$rc" 0
grep -q '^found=true$' "$tmp/gh" && ok "action found=true" || bad "action found=true"
grep -q '^notes<<CLEOF_' "$tmp/gh" && ok "action heredoc notes" || bad "action heredoc notes"
grep -q '^old$' "$tmp/gh" && ok "action notes content" || bad "action notes content"
: > "$tmp/gh"; out="$(act "$tmp/v.md" 7.7.7 true)"; rc=$?
eq "required missing fails" "$rc" 1
case "$out" in *'::error::'*'7.7.7'*"$tmp/v.md"*) ok "error names file and version" ;; *) bad "error names file and version" "$out" ;; esac
: > "$tmp/gh"; out="$(act "$tmp/e.md" 1.0.0 true)"; eq "required empty fails" "$?" 1
: > "$tmp/gh"; out="$(act "$tmp/v.md" 7.7.7 false)"; rc=$?
eq "optional missing passes" "$rc" 0
grep -q '^found=false$' "$tmp/gh" && ok "optional missing found=false" || bad "optional missing found=false"
: > "$tmp/gh"; act "$tmp/l.md" latest true >/dev/null
grep -q '^version=3.1.0$' "$tmp/gh" && ok "action latest version output" || bad "action latest version output"

echo; echo "$pass passed, $failn failed"
[ "$failn" -eq 0 ]
