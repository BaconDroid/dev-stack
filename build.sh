#!/bin/sh
# Local build helper (CI builds the published image on ghcr.io).
set -eu
cd -- "$(dirname -- "$0")"

TAG="${TAG:-dev-stack:local}"
docker build -t "${TAG}" "$@" .
echo "Built ${TAG}"
