#!/bin/sh
# Local build helper (CI builds the published image on ghcr.io).
#
# Tool versions come from versions.sh, i.e. the current upstream release.
set -eu
cd -- "$(dirname -- "$0")"

TAG="${TAG:-dev-stack:local}"

versions=$(sh ./versions.sh)
for kv in $versions; do
    set -- --build-arg "$kv" "$@"
done

docker build -t "${TAG}" "$@" .
echo "Built ${TAG}"
