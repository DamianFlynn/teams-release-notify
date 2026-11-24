#!/usr/bin/env bash
# Entry point for the changelog composite action. Reads CL_PATH, CL_VERSION, CL_REQUIRED
# and writes found / notes / version to $GITHUB_OUTPUT (stdout when unset).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${GITHUB_OUTPUT:-/dev/stdout}"
path="${CL_PATH:-CHANGELOG.md}"
version="${CL_VERSION:-}"
required="${CL_REQUIRED:-true}"
require_ref="${CL_REQUIRE_REFERENCE:-false}"

found=false; notes=""; heading=""
if body="$("$here/changelog-section.sh" "$path" "$version" body)"; then
  heading="$("$here/changelog-section.sh" "$path" "$version" heading)"
  notes="$body"
  [ -n "$notes" ] && found=true
fi

# Every bullet needs a PR reference (#123) or a commit SHA (7-40 hex chars with at least one digit).
unref=""
if [ "$found" = true ] && [ "$require_ref" = true ]; then
  while IFS= read -r line; do
    case "$line" in
      [[:space:]]*[-*]\ *|[-*]\ *) ;;
      *) continue ;;
    esac
    if printf '%s\n' "$line" | grep -Eq '(^|[^[:alnum:]&])#[0-9]+([^[:alnum:]]|$)'; then continue; fi
    if printf '%s\n' "$line" | grep -Eo '(^|[^[:alnum:]])[0-9a-f]{7,40}([^[:alnum:]]|$)' | grep -q '[0-9]'; then continue; fi
    unref="${unref}${line}"$'\n'
  done <<< "$notes"
fi

delim="CLEOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
{
  echo "found=$found"
  echo "version=$heading"
  echo "notes<<$delim"
  printf '%s\n' "$notes"
  echo "$delim"
} >> "$out"

if [ -n "$unref" ]; then
  echo "::error::Changelog bullets in $path for '$version' lack a PR (#123) or commit SHA reference:"
  printf '%s' "$unref"
  exit 1
fi

if [ "$found" != true ]; then
  if [ "$required" = true ]; then
    echo "::error::No changelog section for version '$version' (or it is empty) in $path"
    exit 1
  fi
  echo "::warning::No changelog section for version '$version' in $path"
fi
exit 0
