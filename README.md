<div align="center">
    <h1>capsule</h1>
    <h4 align="center">
        A disposable <a href="https://podman.io/">podman</a> sandbox that drops you straight into <a href="https://opencode.ai/">opencode</a> with all permissions granted.
    </h4>
    <p>The container <em>is</em> the sandbox boundary, so the agent can run anything inside it without prompting, while your host stays untouched.</p>
</div>

<p align="center">
    <a href="https://github.com/eikendev/capsule/actions"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/eikendev/capsule/ci.yml?branch=main"/></a>&nbsp;
    <a href="https://github.com/eikendev/capsule/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/eikendev/capsule"/></a>&nbsp;
</p>

## 🚀 Usage

```sh
make login    # paste your OpenRouter API key once (stored in podman's secret store)
make          # build (first run) and drop into opencode
make shell    # same sandbox, but a bash prompt instead of opencode
make logout   # forget the stored key
make rebuild  # rebuild the image from scratch
make clean    # remove the image + prune dangling images and build cache
make prune    # just reclaim disk (dangling images + build cache), keep the image
make purge    # full reset: image, cache, token, AND your data dir
make where    # print the mounted host directory
make test     # lint Containerfile and Makefile
```

## 🧹 Keeping podman disk usage down

Iterating on the `Containerfile` leaves untagged `<none>` images and build-cache
layers piling up. `make clean` removes the `capsule` image and then runs
`podman image prune -f` + `podman builder prune -f` to sweep those up; `make
prune` does just the sweep without touching the image. Note the prune commands
clear *all* dangling images and build cache on the machine, not only capsule's.
That's normal podman hygiene, but worth knowing if you build other images too.

## 🔑 Authentication

Auth is deliberately kept **separate from your files**. Your OpenRouter API key
(from [openrouter.ai/keys](https://openrouter.ai/keys)) is stored once via
`make login` into **podman's secret store**, not in this repo and not in the
mounted workspace.

At launch, podman mounts the key as a **tmpfs file** at
`/run/secrets/capsule-openrouter-key`, and opencode reads it directly through the
`{file:...}` reference in `opencode.json`. The key therefore lives only in
podman's secret store and in container RAM; it is **never written to your
persistent workspace or the image**.

To rotate the key, just `make login` again.

## ⚡ Token savings (rtk)

The image bakes in [rtk](https://github.com/rtk-ai/rtk) ("Rust Token Killer"),
which compresses noisy command output before it reaches the model, typically
cutting 60-90% of tokens on common dev commands. At build time the image runs
`rtk init -g --opencode --auto-patch`, which installs an opencode plugin
(`tool.execute.before` hook) plus `RTK.md` instructions under
`~/.config/opencode`. It's on by default: the `rtk` binary lives at
`/usr/local/bin/rtk` and the plugin shells out to it transparently. Telemetry is
disabled (`RTK_TELEMETRY_DISABLED=1`).

## 📦 Installing packages inside the sandbox

The `dev` user has **passwordless sudo restricted to apt**, so you (or the
agent) can install tooling on the fly:

```sh
sudo apt install <pkg>
```

## 💾 Persistence

Everything else lives under one directory, with your workspace and opencode's
own state kept as separate siblings:

```
${XDG_DATA_HOME:-~/.local/share}/capsule/
├── work/            ->  /work                          (your workspace)
└── .opencode-data/  ->  ~/.local/share/opencode (in-container)  (session history)
```

The image is disposable (`--rm`); this directory, plus the podman secret, is
what survives between runs. Override the location with
`make CAPSULE_DIR=/some/path`.

## 🥙 Preinstalled tooling

Baked into the image: `git`, `ripgrep`, `curl`, `unzip`, **Python 3**
(`python3`, `pip`, `venv`, with `python` aliased to `python3`), a C/C++
toolchain (`build-essential`: gcc, g++, make), and debugging tools `gdb`,
`strace`, `ltrace`, plus `jq` for JSON.

`strace`/`ltrace`/`gdb` need the `SYS_PTRACE` capability to attach to
processes, which podman denies by default. `RUN_FLAGS` in the Makefile adds
`--cap-add=SYS_PTRACE` to restore it.
