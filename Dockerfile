# dev-stack — dev tooling for coding agents.
#
# One Debian-stable image that runs the Orca headless runtime (`orca serve`) and
# ships the agent CLIs it spawns in worktrees: opencode, git, gh, glab.
# Nothing is installed at runtime; every tool is baked and pinned.
#
# Build:   ./build.sh            (or: docker build -t dev-stack:local .)
# Runtime: add `--init` (Orca must not be PID 1).
FROM debian:13-slim

# Pinned upstream versions. Bump these to upgrade.
ARG GH_VERSION=2.102.0
ARG GLAB_VERSION=1.120.0
ARG OPENCODE_VERSION=1.18.34
ARG ORCA_VERSION=v1.4.218

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    PATH=/root/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Electron + Xvfb runtime for Orca, plus git tooling.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl file jq tar xvfb git \
      libgtk-3-0t64 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libgbm1 libasound2t64 \
      libxtst6 libcups2t64 libdrm2 libxkbcommon0 libpango-1.0-0 libcairo2 libatspi2.0-0t64 \
      libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxrender1 libx11-xcb1 \
      libxcb-dri3-0 libxss1; \
    rm -rf /var/lib/apt/lists/*

# GitHub CLI + GitLab CLI from pinned release tarballs.
RUN set -eux; \
    curl -fsSL -o /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz"; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    curl -fsSL -o /tmp/glab.tar.gz \
      "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz"; \
    tar -xzf /tmp/glab.tar.gz -C /tmp bin/glab; \
    install -m 0755 /tmp/bin/glab /usr/local/bin/glab; \
    rm -rf /tmp/gh.tar.gz /tmp/glab.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64" /tmp/bin

# opencode CLI. The official installer lands in /root/.opencode/bin, which is on
# PATH above and is one of the install dirs Orca scans for agents.
RUN set -eux; \
    curl -fsSL https://opencode.ai/install | bash -s -- --version "${OPENCODE_VERSION}"; \
    opencode --version

# Orca runtime: extract the AppImage so no FUSE device is needed in Docker.
RUN set -eux; \
    mkdir -p /opt/orca; \
    curl -fL -o /opt/orca/orca-linux.AppImage \
      "https://github.com/stablyai/orca/releases/download/${ORCA_VERSION}/orca-linux.AppImage"; \
    chmod 0755 /opt/orca/orca-linux.AppImage; \
    cd /opt/orca; \
    ./orca-linux.AppImage --appimage-extract >/dev/null; \
    rm -f /opt/orca/orca-linux.AppImage; \
    chmod -R a+rX /opt/orca/squashfs-root

COPY entrypoint.sh /usr/local/bin/dev-stack-entrypoint
RUN chmod 0755 /usr/local/bin/dev-stack-entrypoint

# orca serve (WebSocket). Clients pair via the LAN/Tailscale address.
EXPOSE 6768
ENTRYPOINT ["/usr/local/bin/dev-stack-entrypoint"]
