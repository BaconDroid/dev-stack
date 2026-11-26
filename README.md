# dev-stack

Docker image bundling dev tooling for coding agents, on **Debian stable**:

- **[Orca](https://github.com/stablyai/orca)** - headless agent development
  environment (`orca serve`), which spawns the agent CLIs in git worktrees.
- **[opencode](https://opencode.ai)** CLI.
- `git`, `git-lfs`, **GitHub CLI** (`gh`), **GitLab CLI** (`glab`).
- **Node.js 22 LTS** + `npm`, and **bun** - JS runtimes and package managers.
- **Language toolchains:** C (`gcc`/`make`/`pkg-config`, so `cargo check` /
  `cargo test` / `clippy` can link), Rust via rustup (pinned `RUST_VERSION`:
  `cargo`, `rustc`, `rustfmt`, `clippy`, `rust-analyzer`), Go + `golangci-lint`
  (pinned `GOLANGCI_LINT_VERSION`), Python 3 (`pip`, `venv`, `poetry`), Lua
  (`luajit`, `luacheck` installed exactly as rakuyomi's CI does, and `busted`
  running the plugin specs under LuaJIT).
- `cmake`, `gdb`, `fish`, `zsh`.
- `tmux`, `ripgrep` (`rg`), `fd-find`, `openssh-client` (git over SSH), `tzdata`,
  `jq`, `curl`, `unzip`/`zip`, `less`, `procps`.

Everything is baked at build time and pinned as `ARG`s in the `Dockerfile`
(`GH_VERSION`, `GLAB_VERSION`, `OPENCODE_VERSION`, `ORCA_VERSION`,
`RUST_VERSION`, `GOLANGCI_LINT_VERSION`). Nothing is installed at runtime.

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
  -e GITLAB_TOKEN=... \
  -e OPEN_DESIGN_API_KEY=... \
  -e QCODE_API_KEY=... \
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

## GitLab token (optional)

Set `GITLAB_TOKEN` and the entrypoint logs `glab` in and adds a git credential
helper for HTTPS clones. The host defaults to `gitlab.com`; set `GITLAB_HOST`
for a self-managed instance. The token is stored in plaintext in glab's config
because the container has no keyring; the git helper reads it from the
environment and never writes it to `.gitconfig`.

## open-design API key (optional)

Set `OPEN_DESIGN_API_KEY` (key for <https://go.open-design.ai/>) and the
entrypoint stores it in opencode's `auth.json` under the provider id
`open-design`, keeping any other stored credentials. The provider itself
(`baseURL`, models) must still be declared in the opencode config under
`/root/.config/opencode`. `auth.json` lives in `~/.local/share/opencode`, which
is not a volume in the example above, so the key is re-seeded on every start.

## AIReiter API key (optional)

Set `AIREITER_API_KEY` (key for the Coding Plan, <https://aireiter.com/coding-plan>)
and the entrypoint stores it in opencode's `auth.json` under **both** provider ids of
that plan - `aireiter` (OpenAI-compatible) and `aireiter-anthropic` (Anthropic
Messages) - because one plan and one key serve the two endpoints. Any other stored
credential is kept, and the file is left mode 600.

The provider itself (`baseURL`, models) must still be declared in the opencode config
under `/root/.config/opencode`, where it reads the key as `{env:AIREITER_API_KEY}`. Both
paths therefore see the same value, and the seeding re-reads the environment at every
start, so a rotated key never leaves a stale entry behind.

Credential seeding runs before anything else and can be exercised on its own, without
starting the runtime:

```sh
sh entrypoint.sh --seed-only
```

## QCode key (optional)

Set `QCODE_API_KEY` (key for a QCode plan, <https://qcode.cc/en/pricing>) and the
entrypoint stores it in opencode's `auth.json` under both provider ids, `qcode` and
`qcode-chat`, keeping any other stored credential and leaving the file mode 600.

`unraid-stack`'s overlay declares both. `qcode` is `@ai-sdk/anthropic` on
`https://api.qcode.cc/claude/v1` and carries the Claude family; `qcode-chat` is
`@ai-sdk/openai-compatible` on `https://api.qcode.cc/openai/v1` and carries GPT plus
GLM, Kimi, DeepSeek and Qwen. QCode bills one shared quota across every family, so the
single key serves both legs. Both base URLs must keep `/v1`: opencode's Anthropic client
appends `/messages` and nothing else, so a shortened `/api` answers
`Not Found: Route /api/messages not found`. The Chinese families are reachable only on
the OpenAI-compatible leg - Codex's Responses protocol does not serve them - which is
why `qcode-chat` uses `@ai-sdk/openai-compatible` rather than `@ai-sdk/openai`; the GPT
ids also answer on the Responses interface if that leg ever regresses. Keys are prefixed
`cr_` and are minted per account, so the same key reaches every model on the plan.

## OpenCode Go and Command Code keys (optional)

`OPENCODE_API_KEY` (OpenCode Zen + Go) and `CMD_API_KEY` (Command Code GOAT) already
work without the entrypoint: both providers are built into opencode, which reads those
two variables from the environment. The entrypoint **also** stores them in
`auth.json` under the `opencode-go` and `commandcode` provider ids, so every
subscription lives in one store and a config override that drops the built-in
convention still finds the key. Nothing else changes: a missing variable seeds nothing.

All the subscriptions therefore appear in one place:

```sh
docker exec dev-stack sh -c 'jq -r "keys[]" ~/.local/share/opencode/auth.json'
```

## opencode server (optional)

Set `OPENCODE_SERVE_PORT` (e.g. `4096`) and publish `-p 4096:4096` to also run a
headless `opencode serve` alongside Orca, for direct TUI/web attach. Set
`OPENCODE_SERVER_PASSWORD` to require auth - otherwise the server logs
`server is unsecured` and is open to anyone who can reach the port.

## Remote terminals

`bash -l` (what an interactive remote terminal usually spawns) does not inherit
the image's `PATH`: Debian's `/etc/profile` rewrites it. `/etc/profile.d/10-dev-stack-path.sh`
puts `/root/.opencode/bin`, `/root/.bun/bin` and `/root/.cargo/bin` back, so
`opencode` and `cargo` work in login shells. If you hit `command not found`,
either shell is not reading the profile or you are on an image older than that
file - then use the absolute path:

```sh
cd /workspace/<project> && /root/.opencode/bin/opencode
```

`OPENCODE_CONFIG` is baked into the environment (not the profile), so a custom
config pointer survives a login shell; if the file it points at is missing the
entrypoint drops it with a warning instead of failing every agent run.

## Version parity

`ORCA_VERSION` in the `Dockerfile` must match the desktop app: client and runtime
from different releases is the usual cause of "it paired fine yesterday" and of
odd terminal behaviour. The pinned value is the currently released tag on
<https://github.com/stablyai/orca/releases/latest>; the image exports it as the
`ORCA_VERSION` environment variable so a deployed container can be compared with
a client at any time. `unraid-stack`'s `verify-dev-stack.sh` does that comparison
and reports drift.

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
