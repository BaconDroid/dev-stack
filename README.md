# dev-stack

Docker image bundling dev tooling for coding agents, on **Debian stable**:

- **[Orca](https://github.com/stablyai/orca)** — headless agent development
  environment (`orca serve`), which spawns the agent CLIs in git worktrees.
- **[opencode](https://opencode.ai)** CLI.
- `git`, **GitHub CLI** (`gh`), **GitLab CLI** (`glab`).
- **Node.js 22 LTS** + `npm`, and **bun** — JS runtimes and package managers.
- `tmux`, `ripgrep` (`rg`), `fd-find`, `openssh-client` (git over SSH), `tzdata`,
  `jq`, `curl`, `unzip`/`zip`, `less`, `procps`.

Everything is baked at build time and pinned as `ARG`s in the `Dockerfile`
(`GH_VERSION`, `GLAB_VERSION`, `OPENCODE_VERSION`, `ORCA_VERSION`). Nothing is
installed at runtime.

## Image

Published to GHCR by GitHub Actions on every push to `main` and every `v*` tag:

```
ghcr.io/bacondroid/dev-stack:latest
ghcr.io/bacondroid/dev-stack:sha-<short>
```

## Run

```sh
docker run -d --name dev-stack --init \
  -p 6768:6768 \
  -e ORCA_PAIRING_ADDRESS=<LAN-or-Tailscale-IP> \
  -e GIT_USER_NAME=you -e GIT_USER_EMAIL=you@example.com \
  -e GITHUB_PERSONAL_ACCESS_TOKEN=... \
  -v devstack-orca:/root/.config/orca \
  -v devstack-orca-upper:/root/.config/Orca \
  -v devstack-opencode:/root/.config/opencode \
  -v "$PWD":/workspace \
  ghcr.io/bacondroid/dev-stack:latest
```

- `--init` is **required**: Orca must not be PID 1.
- `serve` listens on `6768` and prints a ready block on stdout with the pairing
  URL:

  ```sh
  docker logs dev-stack | grep -i pairing
  ```

## opencode server (optional)

Set `OPENCODE_SERVE_PORT` (e.g. `4096`) and publish `-p 4096:4096` to also run a
headless `opencode serve` alongside Orca, for direct TUI/web attach.

## Pairing

The pairing URL (`orca://pair?code=...`) is a **capability — treat it like a
password**: it carries the device token and the E2EE key. Never expose port
`6768` to the public Internet; use LAN / Tailscale / WireGuard.

Orca persists its state (device registry, E2EE keypair, projects, worktree
metadata, terminal history) under `/root/.config/orca` **and**
`/root/.config/Orca`. Both must be on a volume or the pairing is lost on
recreate.

## Notes

- **Root + `--no-sandbox`.** The entrypoint runs as root and adds
  `--no-sandbox` (Electron refuses its sandbox as root). To run unprivileged,
  add a user and remap the `~/.config` paths.
- **Agent discovery is PATH-based.** Orca scans `~/.opencode/bin` (where the
  installer places opencode) among other install dirs; no config file needed.
- **Headless display.** Orca starts Xvfb itself when `DISPLAY` is unset;
  `xvfb` is installed and `LIBGL_ALWAYS_SOFTWARE=1` avoids GPU/DRM warnings.
- **No official Orca image exists**; this image is built here.

## Build locally

```sh
./build.sh                 # -> dev-stack:local
TAG=dev-stack:test ./build.sh
```

## License

MIT — see [LICENSE](LICENSE). Upstream tools keep their own licenses.
