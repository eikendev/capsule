FROM ubuntu:24.04

# UID/GID are passed from the host at build time so bind-mounted files stay
# writable and owned by you (see Makefile: --build-arg UID=$(id -u) ...).
ARG UID=1000
ARG GID=1000

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git ripgrep sudo unzip \
        python3 python3-pip python3-venv python-is-python3 \
        build-essential gdb strace ltrace jq \
    && rm -rf /var/lib/apt/lists/*

# rtk (Rust Token Killer) compresses command output to cut LLM token use.
# Installed to /usr/local/bin (on PATH) as root so the opencode plugin can shell
# out to it at runtime. Telemetry off by default.
ENV RTK_TELEMETRY_DISABLED=1
# bash -c + set -o pipefail so a dropped curl fails the build instead of
# silently piping nothing into sh. A global SHELL directive won't do this:
# podman's default OCI image format ignores SHELL entirely (docker format
# doesn't), so it has to be set explicitly per RUN instead.
RUN bash -c 'set -o pipefail && curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
      | RTK_INSTALL_DIR=/usr/local/bin sh'

# Ubuntu 24.04 ships a default 'ubuntu' user at uid 1000; drop it so we can
# create 'dev' at whatever UID/GID the host uses.
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd -g "$GID" dev 2>/dev/null || true \
 && useradd -l -m -u "$UID" -g "$GID" -s /bin/bash dev

# Passwordless sudo, restricted to apt only, which is enough for installing
# packages without opening up full root. Safe regardless since the container
# is the boundary. Note: anything installed this way is lost on exit (--rm);
# for lasting tools, add them to this Containerfile instead.
RUN echo 'dev ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get' > /etc/sudoers.d/dev \
 && chmod 0440 /etc/sudoers.d/dev

# Pre-create every XDG dir opencode writes to, owned by dev. Otherwise podman
# auto-creates the bind-mount's parent dirs (.local, .local/share) as container
# root (an unwritable subuid under --userns=keep-id), and opencode fails with
# EACCES trying to mkdir e.g. ~/.local/state.
# All permissions granted: this is safe because the container is the sandbox
# boundary.
RUN mkdir -p /home/dev/.config/opencode \
             /home/dev/.local/share/opencode \
             /home/dev/.local/state \
             /home/dev/.cache
COPY opencode.json /home/dev/.config/opencode/opencode.json
RUN chown -R "$UID:$GID" /home/dev

USER dev
ENV HOME=/home/dev
ENV PATH=/home/dev/.opencode/bin:$PATH

# Installs the opencode binary to $HOME/.opencode/bin, then wires rtk into it
# globally (installs the tool.execute.before plugin and RTK.md instructions
# under ~/.config/opencode; --auto-patch = non-interactive). Chained into one
# RUN since the second step depends on the first having completed anyway.
RUN bash -c 'set -o pipefail && curl -fsSL https://opencode.ai/install | bash' \
 && rtk init -g --opencode --auto-patch

WORKDIR /work
CMD ["opencode"]
