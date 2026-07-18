#!/bin/bash
# wsl-cache.sh — per-user, per-namespace plain-text cache helpers.
#
# Sourced (not executed) by provisioning scripts and runtime code that need to
# persist and later read small plain-text values on disk. A cache entry is a
# single file whose name is the cache-name and whose content is the cache string.
#
# The two access patterns are asymmetric on purpose:
#   * writes happen at provisioning time (typically as root, into a target user's
#     home), so the owner is passed explicitly and its home is resolved from that
#     owner via getent passwd;
#   * reads happen at call time as the user themselves, so the owner is the
#     invoking user (id -un).
# XDG_CACHE_HOME is intentionally not consulted; homes come from getent passwd.
#
# It is installed as a durable runtime bundle at /usr/local/lib/wsl-cloud-init/.
# Callers own `set -euo pipefail`; this file deliberately does not.
#
#   source /usr/local/lib/wsl-cloud-init/wsl-cache.sh
#   wsl_cache_set "$TARGET_USER" powershell-path interop "$path"
#   path="$(wsl_cache_get powershell-path interop)"
#   age="$(wsl_cache_age powershell-path interop)"  # seconds since write, or miss

# ---------------------------------------------------------------------------
# Private plumbing (leading underscore): not part of the public API.
# ---------------------------------------------------------------------------

# Resolve a user's home directory from the passwd database. Echoes the home path,
# or fails with a message.
#
#   _wsl_cache_home <owner>
#
# <owner> user whose home directory (passwd field 6) is looked up.
_wsl_cache_home() {
  local owner="$1" home
  home="$(getent passwd "$owner" | cut -d: -f6)"
  if [[ -z "$home" ]]; then
    echo "wsl-cache: could not resolve home directory for user '$owner'" >&2
    return 1
  fi
  printf '%s\n' "$home"
}

# Validate a single path segment used to build the cache path. Rejects anything
# that could escape the cache tree: characters outside a conservative filename
# set (notably '/'), or the special names "." and "..".
#
#   _wsl_cache_valid_segment <kind> <value>
#
# <kind>  human-readable label for the error message (e.g. cache-name).
# <value> the segment to validate.
_wsl_cache_valid_segment() {
  local kind="$1" value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ || "$value" == "." || "$value" == ".." ]]; then
    echo "wsl-cache: invalid $kind '$value' (allowed: A-Z a-z 0-9 . _ -; not '.' or '..')" >&2
    return 1
  fi
}

# Resolve the on-disk path of a cache entry belonging to the invoking user. Both
# segments are validated and the invoking user's home is looked up from passwd.
# Echoes the full path; does not check that the file exists.
#
#   _wsl_cache_file <name> <namespace>
#
# <name>      cache entry name (on-disk filename).
# <namespace> subdirectory the entry lives under.
_wsl_cache_file() {
  local name="$1" namespace="$2"

  _wsl_cache_valid_segment cache-name "$name" || return 1
  _wsl_cache_valid_segment cache-namespace "$namespace" || return 1

  local owner home
  owner="$(id -un)" || return 1
  home="$(_wsl_cache_home "$owner")" || return 1
  printf '%s\n' "$home/.cache/wsl-cloud-init/$namespace/$name"
}

# ---------------------------------------------------------------------------
# Public API: bash functions operating on <home>/.cache/wsl-cloud-init/<namespace>/.
# ---------------------------------------------------------------------------

# Create or replace a cache entry, owned by the given owner.
#
#   wsl_cache_set <owner> <name> <namespace> <cache>
#
# <owner>     user that owns the cache directory and file (home resolved via getent).
# <name>      cache entry name; becomes the on-disk filename.
# <namespace> groups related entries under a subdirectory.
# <cache>     text content written verbatim to the file (may span multiple lines, and
#             may be empty — an empty string writes a 0-byte cache file).
#
# Writes <owner-home>/.cache/wsl-cloud-init/<namespace>/<name>. Both the directory
# and the file are owned by <owner>. A missing argument is an error (an empty <cache>
# is written, but the argument itself must be present).
wsl_cache_set() {
  local owner="$1" name="$2" namespace="$3" cache="$4"

  if [[ -z "$owner" ]]; then
    echo "wsl-cache: cache-owner is required" >&2
    return 1
  fi
  if [[ -z "$name" ]]; then
    echo "wsl-cache: cache-name is required" >&2
    return 1
  fi
  if [[ -z "$namespace" ]]; then
    echo "wsl-cache: cache-namespace is required" >&2
    return 1
  fi
  if [[ $# -lt 4 ]]; then
    echo "wsl-cache: cache is required" >&2
    return 1
  fi

  _wsl_cache_valid_segment cache-name "$name" || return 1
  _wsl_cache_valid_segment cache-namespace "$namespace" || return 1

  local home dir dest tmp rc
  home="$(_wsl_cache_home "$owner")" || return 1
  dir="$home/.cache/wsl-cloud-init/$namespace"
  dest="$dir/$name"

  install -d -o "$owner" -g "$owner" "$dir" || return 1

  tmp="$(mktemp)" || return 1
  printf '%s' "$cache" > "$tmp"
  install -m 0644 -o "$owner" -g "$owner" "$tmp" "$dest"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# Read a cache entry belonging to the invoking user.
#
#   wsl_cache_get <name> <namespace>
#
# <name>      cache entry name (on-disk filename).
# <namespace> subdirectory the entry lives under.
#
# Reads <invoking-user-home>/.cache/wsl-cloud-init/<namespace>/<name> and echoes its
# content verbatim. A cache miss yields empty output and success (return 0). A missing
# mandatory argument is an error.
wsl_cache_get() {
  local name="$1" namespace="$2"

  if [[ -z "$name" ]]; then
    echo "wsl-cache: cache-name is required" >&2
    return 1
  fi
  if [[ -z "$namespace" ]]; then
    echo "wsl-cache: cache-namespace is required" >&2
    return 1
  fi

  local file
  file="$(_wsl_cache_file "$name" "$namespace")" || return 1

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  cat "$file"
}

# Report the age in whole seconds of a cache entry belonging to the invoking user.
#
#   wsl_cache_age <name> <namespace>
#
# <name>      cache entry name (on-disk filename).
# <namespace> subdirectory the entry lives under.
#
# Echoes (now - mtime) in seconds for
# <invoking-user-home>/.cache/wsl-cloud-init/<namespace>/<name>. On a cache miss
# (file absent) echoes nothing and returns 1, so callers can treat "missing" and
# "stale" uniformly. A missing mandatory argument is an error.
wsl_cache_age() {
  local name="$1" namespace="$2"

  if [[ -z "$name" ]]; then
    echo "wsl-cache: cache-name is required" >&2
    return 1
  fi
  if [[ -z "$namespace" ]]; then
    echo "wsl-cache: cache-namespace is required" >&2
    return 1
  fi

  local file mtime now
  file="$(_wsl_cache_file "$name" "$namespace")" || return 1

  [[ -f "$file" ]] || return 1

  mtime="$(stat -c %Y "$file")" || return 1
  now="$(date +%s)"
  printf '%s\n' "$(( now - mtime ))"
}
