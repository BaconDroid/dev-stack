#!/bin/sh
# dev-stack entrypoint: seed git/gh auth from the environment, then start the
# Orca runtime in headless mode (docs/reference/headless-linux-server.md).
set -eu

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PATH="/root/.opencode/bin:${PATH}"

# Git identity for commits made by the agents.
GIT_USER_NAME="${GIT_USER_NAME:-BaconDroid}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-11067111+BaconDroid@users.noreply.github.com}"
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

# Seed gh from the token and install git's credential helper (HTTPS clones).
if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    printf '%s' "${GITHUB_PERSONAL_ACCESS_TOKEN}" | gh auth login --with-token 2>/dev/null || true
    gh auth setup-git 2>/dev/null || true
fi

# Optional headless opencode server, for direct TUI/web attach on its own port.
if [ -n "${OPENCODE_SERVE_PORT:-}" ]; then
    opencode serve --port "${OPENCODE_SERVE_PORT}" --hostname 0.0.0.0 >/var/log/opencode-serve.log 2>&1 &
fi

# Orca's state dir is a volume (see README: /root/.config/orca, plus the
# case-sensitive twin). Persisting it keeps the E2EE keypair, the runtime id and
# the paired-device tokens across recreations - without it every new container
# is a new server identity and clients have to pair again.
#
# The flip side: transient runtime artifacts also survive the restart. A
# SingletonLock, a unix socket and a pid file left behind by a killed process
# make the next start wait on a dead endpoint, so drop them before serving.
# Identity files (orca-e2ee-keypair.json, orca-devices.json, *.token) are never
# touched here.
for d in "${ORCA_CONFIG_DIR:-/root/.config/orca}" /root/.config/Orca; do
    rm -f "$d"/Singleton* "$d"/o-*.sock "$d"/daemon/*.pid "$d"/daemon/*.sock 2>/dev/null || true
done

# Build the `serve` argv.
set -- serve --port "${ORCA_PORT:-6768}"
if [ -n "${ORCA_PAIRING_ADDRESS:-}" ]; then
    set -- "$@" --pairing-address "${ORCA_PAIRING_ADDRESS}"
fi
# Electron refuses to start as root with its sandbox enabled (headless doc).
if [ "$(id -u)" = "0" ]; then
    set -- --no-sandbox "$@"
fi

exec /opt/orca/squashfs-root/AppRun "$@"
