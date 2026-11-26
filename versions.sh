#!/bin/sh
# Prints KEY=VALUE for each baked tool, resolved to its latest upstream release.
# build.sh and CI turn each line into a --build-arg. Export PIN_<NAME> to pin one.
set -eu

github_tag() {
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest")
    printf '%s' "${url##*/}"
}

emit() {
    [ -n "$2" ] || { echo "versions.sh: $1 resolved to nothing" >&2; exit 1; }
    pinned=$(printenv "PIN_$1" || true)
    printf '%s=%s\n' "$1" "${pinned:-$2}"
}

emit GH_VERSION "$(github_tag cli/cli | sed 's/^v//')"

emit GLAB_VERSION "$(
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest)
    printf '%s' "${url##*/}" | sed 's/^v//'
)"

emit OPENCODE_VERSION "$(
    curl -fsSL https://opencode.ai/update/api/latest/cli/npm \
        | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
)"

emit ORCA_VERSION "$(github_tag stablyai/orca)"

emit RUST_VERSION "$(
    curl -fsSL https://static.rust-lang.org/dist/channel-rust-stable.toml \
        | awk '/^\[pkg\.rustc\]/{getline; print}' \
        | sed -n 's/^version = "\([0-9][0-9.]*\).*/\1/p'
)"

emit GOLANGCI_LINT_VERSION "$(github_tag golangci/golangci-lint | sed 's/^v//')"
