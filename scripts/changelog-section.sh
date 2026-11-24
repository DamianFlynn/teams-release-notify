#!/usr/bin/env bash
# Extract one section from a changelog.
#   changelog-section.sh <file> <version|latest> body|heading
# Exit codes: 0 found, 3 section missing, 2 usage / file error.
# A "## " heading matches when its first token (after an optional "[" and "v",
# up to a space, "]" or "(") equals the version (a leading "v" on the input is ignored).
# "latest" selects the first "## " section that is not "Unreleased".
set -u

file="${1:-}"; version="${2:-}"; mode="${3:-body}"
if [ -z "$file" ] || [ -z "$version" ]; then
  echo "usage: changelog-section.sh <file> <version|latest> body|heading" >&2
  exit 2
fi
if [ ! -f "$file" ]; then
  echo "changelog file not found: $file" >&2
  exit 2
fi

awk -v want="$version" -v mode="$mode" '
function token(h) {
  sub(/^##[ \t]+/, "", h)
  sub(/^\[/, "", h)
  sub(/[ \t\]\(].*$/, "", h)
  return h
}
function bare(t) { sub(/^[vV]/, "", t); return t }
BEGIN { insec = 0; found = 0; n = 0; wantb = bare(want) }
{
  sub(/\r$/, "")
  if ($0 ~ /^##[ \t]/) {
    if (insec) exit
    t = token($0)
    ok = 0
    if (want == "latest") { ok = (tolower(t) != "unreleased") }
    else { ok = (bare(t) == wantb) }
    if (ok) { insec = 1; found = 1; heading = t; next }
    next
  }
  if (insec) lines[n++] = $0
}
END {
  if (!found) exit 3
  if (mode == "heading") { print heading; exit 0 }
  s = 0; e = n - 1
  while (s <= e && lines[s] ~ /^[ \t]*$/) s++
  while (e >= s && lines[e] ~ /^[ \t]*$/) e--
  for (i = s; i <= e; i++) print lines[i]
}
' "$file"
