<div align="center">
    <h1>capsule</h1>
    <h4 align="center">
        A disposable <a href="https://podman.io/">podman</a> sandbox that drops you straight into <a href="https://opencode.ai/">opencode</a> or <a href="https://docs.claude.com/en/docs/claude-code">Claude Code</a> with all permissions granted.
    </h4>
    <p>The container <em>is</em> the sandbox boundary, so the agent can run anything inside it without asking while your host stays untouched.</p>
</div>

<p align="center">
    <a href="https://github.com/eikendev/capsule/actions"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/eikendev/capsule/ci.yml?branch=main"/></a>&nbsp;
    <a href="https://github.com/eikendev/capsule/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/eikendev/capsule"/></a>&nbsp;
</p>

## 🚀 Usage

```sh
make login    # paste your OpenRouter API key once (stored in podman's secret store)
make          # build (first run) and drop into opencode (default)
make opencode # same as above, explicit
make claude   # build (first run) and drop into Claude Code instead
make shell    # same sandbox, but a bash prompt with both agents' data mounted
make logout   # forget the stored OpenRouter key
make rebuild  # rebuild the image from scratch
make clean    # remove the image + prune dangling images and build cache
make prune    # just reclaim disk (dangling images + build cache), keep the image
make purge    # full reset: image, cache, token, AND your data dir
make where    # print the mounted host directory
make test     # lint Containerfile and Makefile
```

Both targets run the same image and only differ in the command they launch (`opencode` or `claude`).
`make claude` doesn't need `make login`, because Claude Code asks you to log in on first run (see [Authentication](#-authentication)).

## 🧹 Keeping podman disk usage down

Iterating on the `Containerfile` leaves behind untagged `<none>` images and build-cache layers.
`make clean` removes the `capsule` image and then runs `podman image prune -f` and `podman builder prune -f` to clean those up.
`make prune` runs only the cleanup and keeps the image.
The prune commands clear all dangling images and build cache on the machine, including those from other projects, so keep that in mind if you build other images too.

## 🔑 Authentication

Each agent authenticates its own way, and neither keeps its credentials with your files.

opencode uses an OpenRouter API key from [openrouter.ai/keys](https://openrouter.ai/keys).
`make login` stores it once in podman's secret store, outside this repo and the mounted workspace.
At launch, podman mounts the key as a tmpfs file at `/run/secrets/capsule-openrouter-key`, and opencode reads it through the `{file:...}` reference in `opencode.json`.
The key only exists in podman's secret store and in container memory, so it never ends up in your persistent workspace or the image.
To rotate the key, run `make login` again.

Claude Code has no key to paste.
Run `make claude` and it walks you through its own login on first use (a device-code flow against your Claude.ai or Console account).
The session is saved under `~/.claude` (see [Persistence](#-persistence)), so you only log in once.

`make claude` sets `permissions.defaultMode: "bypassPermissions"` in `~/.claude/settings.json` to skip permission prompts, much like opencode's `"permission": "allow"`.
Claude Code shows a warning dialog about this on first run, and your answer is saved to the persisted `~/.claude`, so you won't see it again.

## ⚡ Token savings (rtk)

The image includes [rtk](https://github.com/rtk-ai/rtk) ("Rust Token Killer"), which compresses noisy command output before the model sees it.
On common dev commands it usually cuts 60-90% of tokens.
At build time the image runs `rtk init -g --opencode --auto-patch`, which installs an opencode plugin (a `tool.execute.before` hook) and `RTK.md` instructions under `~/.config/opencode`.
It's on by default: the plugin calls the `rtk` binary at `/usr/local/bin/rtk` on its own, so you don't have to do anything.
Telemetry is disabled (`RTK_TELEMETRY_DISABLED=1`).

## 📦 Installing packages inside the sandbox

The `dev` user has passwordless sudo for apt only, so you or the agent can install tools as needed:

```sh
sudo apt install <pkg>
```

If you need more than apt, like changing file ownership, mounting things, or running other privileged commands, build with `FULL_SUDO=1` to give `dev` unrestricted passwordless root:

```sh
make FULL_SUDO=1          # or: make claude FULL_SUDO=1, make rebuild FULL_SUDO=1
```

This is off by default.
Turning it on isn't any riskier than the apt-only setup, since the container is the sandbox boundary and root inside it still can't touch your host.

## 💾 Persistence

Everything else lives under one directory, with your workspace and each agent's state in separate subdirectories:

```
${XDG_DATA_HOME:-~/.local/share}/capsule/
├── work/            ->  /work                          (your workspace, shared by both agents)
├── .opencode-data/  ->  ~/.local/share/opencode (in-container)  (opencode session history)
├── .claude-data/    ->  ~/.claude (in-container)                (Claude Code session data)
└── .claude.json     ->  ~/.claude.json (in-container)           (Claude Code config, incl. login)
```

The container is thrown away after each run (`--rm`), so this directory and the podman secret are all that carry over between runs.
To keep it somewhere else, run `make CAPSULE_DIR=/some/path`.

## 🥙 Preinstalled tooling

The image comes with `git`, `ripgrep`, `curl`, `unzip`, Python 3 (`python3`, `pip`, `venv`, with `python` aliased to `python3`), Node.js and `npm`, a C/C++ toolchain (`build-essential`: gcc, g++, make), the debuggers `gdb`, `strace`, and `ltrace`, and `jq` for JSON.

`strace`, `ltrace`, and `gdb` need the `SYS_PTRACE` capability to attach to processes, which podman denies by default.
`COMMON_FLAGS` in the Makefile adds `--cap-add=SYS_PTRACE` so they work.
