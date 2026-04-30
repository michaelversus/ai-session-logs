#!/usr/bin/env bash

make_slug() {
  local dir="$1"
  local slug
  slug="$(cd "$dir" && pwd -P)"
  slug="${slug#/}"
  slug="${slug//\//-}"
  slug="${slug//./-}"
  printf '%s\n' "$slug"
}