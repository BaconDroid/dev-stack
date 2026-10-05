#!/bin/sh
# dev-stack entrypoint: seed git/gh auth from the environment, then start the
# Orca runtime in headless mode (docs/reference/headless-linux-server.md).
set -eu

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PATH="/root/.opencode/bin:${PATH}"

# Git identity for commits made by the agents.
if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "${GIT_USER_NAME}"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "${GIT_USER_EMAIL}"
fi

# Seed gh from the token and install git's credential helper (HTTPS clones).
if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    printf '%s' "${GITHUB_PERSONAL_ACCESS_TOKEN}" | gh auth login --with-token 2>/dev/null || true
    gh auth setup-git 2>/dev/null || true
fi

# Optional headless opencode server, for direct TUI/web attach on its own port.
if [ -n "${OPENCODE_SERVE_PORT:-}" ]; then
    opencode serve --port "${OPENCODE_SERVE_PORT}" --hostname 0.0.0.0 >/var/log/opencode-serve.log 2>&1 &
fi

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
