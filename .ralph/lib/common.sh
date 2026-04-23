#!/usr/bin/env bash

ralph_die() {
  echo "ralph: $*" >&2
  exit 1
}

ralph_usage_error() {
  echo "ralph: $*" >&2
  exit 2
}

ralph_abs_dir() {
  local path="$1"
  mkdir -p "$path" || return 1
  cd "$path" >/dev/null 2>&1 && pwd -P
}
