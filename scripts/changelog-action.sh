#!/usr/bin/env bash
# Entry point for the changelog composite action. Reads CL_PATH, CL_VERSION, CL_REQUIRED
# and writes found / notes / version to $GITHUB_OUTPUT (stdout when unset).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${GITHUB_OUTPUT:-/dev/stdout}"
path="${CL_PATH:-CHANGELOG.md}"
version="${CL_VERSION:-}"
required="${CL_REQUIRED:-true}"

found=false; notes=""; heading=""
if body="$("$here/changelog-section.sh" "$path" "$version" body)"; then
  heading="$("$here/changelog-section.sh" "$path" "$version" heading)"
  notes="$body"
  [ -n "$notes" ] && found=true
fi

delim="CLEOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
{
  echo "found=$found"
  echo "version=$heading"
  echo "notes<<$delim"
  printf '%s\n' "$notes"
  echo "$delim"
} >> "$out"

if [ "$found" != true ]; then
  if [ "$required" = true ]; then
    echo "::error::No changelog section for version '$version' (or it is empty) in $path"
    exit 1
  fi
  echo "::warning::No changelog section for version '$version' in $path"
fi
exit 0
