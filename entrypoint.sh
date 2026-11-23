#!/bin/sh
# dev-stack entrypoint: seed git/gh auth from the environment, then start the
# Orca runtime in headless mode (docs/reference/headless-linux-server.md).
set -eu

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PATH="/root/.opencode/bin:${PATH}"

# A stale OPENCODE_CONFIG (file deleted, or a template pointing at a path that
# never existed) makes every agent run fail on config load. Drop it with a
# warning instead of starting in a broken state; the base config still applies.
if [ -n "${OPENCODE_CONFIG:-}" ] && [ ! -r "${OPENCODE_CONFIG}" ]; then
    echo "dev-stack: OPENCODE_CONFIG=${OPENCODE_CONFIG} is not readable, ignoring it" >&2
    unset OPENCODE_CONFIG
fi

# Seed a provider key into opencode's credential store under its provider id.
# One atomic write per call, merged with jq so keys for other providers are kept.
# The secret is read from jq's own environment, never interpolated into a command
# line, and the file is left mode 600.
seed_provider_key() {
    provider_id="$1"
    env_name="$2"
    auth_file="${XDG_DATA_HOME:-/root/.local/share}/opencode/auth.json"
    mkdir -p "$(dirname "${auth_file}")"
    [ -s "${auth_file}" ] || echo '{}' > "${auth_file}"
    if jq --arg id "${provider_id}" --arg var "${env_name}" \
        '.[$id] = {type: "api", key: env[$var]}' "${auth_file}" > "${auth_file}.tmp"; then
        chmod 600 "${auth_file}.tmp"
        mv "${auth_file}.tmp" "${auth_file}"
    else
        rm -f "${auth_file}.tmp"
        echo "dev-stack: could not seed ${env_name} into ${auth_file}" >&2
    fi
}
# open-design (https://go.open-design.ai/), one provider id.
if [ -n "${OPEN_DESIGN_API_KEY:-}" ]; then
    seed_provider_key open-design OPEN_DESIGN_API_KEY
fi
# AIReiter (https://aireiter.com/coding-plan): one plan, one key, two provider
# ids - the OpenAI-compatible endpoint and the Anthropic Messages one - so both
# legs are seeded from the same variable.
if [ -n "${AIREITER_API_KEY:-}" ]; then
    seed_provider_key aireiter AIREITER_API_KEY
    seed_provider_key aireiter-anthropic AIREITER_API_KEY
fi

# `sh entrypoint.sh --seed-only` runs the credential seeding and stops: it exists
# so the seeding above can be exercised without starting the runtime.
if [ "${1:-}" = "--seed-only" ]; then
    exit 0
fi
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

# Same for glab. The container has no OS keyring, hence --insecure-storage.
# GITLAB_HOST selects a self-managed instance (default gitlab.com). glab 1.120
# has no git credential helper of its own, so HTTPS clones use a helper that
# reads GITLAB_TOKEN from the environment at call time (the token is not
# written to .gitconfig).
if [ -n "${GITLAB_TOKEN:-}" ]; then
    gitlab_host="${GITLAB_HOST:-gitlab.com}"
    printf '%s' "${GITLAB_TOKEN}" | glab auth login --stdin \
        --hostname "${gitlab_host}" --insecure-storage >/dev/null 2>&1 \
        || echo "dev-stack: glab auth login failed for ${gitlab_host}" >&2
    git config --global "credential.https://${gitlab_host}.helper" \
        '!f() { test "$1" = get && printf "username=oauth2\npassword=%s\n" "$GITLAB_TOKEN"; }; f'
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
