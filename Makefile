SHELL         := /bin/bash

IMAGE         ?= capsule
SECRET        ?= capsule-openrouter-key
XDG_DATA_HOME ?= $(HOME)/.local/share
CAPSULE_DIR   ?= $(XDG_DATA_HOME)/capsule
WORK_DIR      := $(CAPSULE_DIR)/work
DATA_DIR      := $(CAPSULE_DIR)/.opencode-data
UID           := $(shell id -u)
GID           := $(shell id -g)

# Shared podman flags.
#   --userns=keep-id  maps your host UID in, so bind-mounted files stay yours.
#   --cap-add=SYS_PTRACE  lets strace/ltrace/gdb attach to processes (denied
#                     by podman's default capability set).
#   --secret          mounts the token as a tmpfs file at /run/secrets/$(SECRET);
#                     opencode reads it via {file:...}, so it never touches disk.
#   :z                relabels bind mounts for SELinux (Fedora).
RUN_FLAGS = --rm -it --userns=keep-id \
	--cap-add=SYS_PTRACE \
	--secret $(SECRET) \
	-v $(WORK_DIR):/work:z \
	-v $(DATA_DIR):/home/dev/.local/share/opencode:z \
	-w /work

.DEFAULT_GOAL := run

.PHONY: run shell login logout build rebuild test clean prune purge where help require-secret

test:                              ## Lint (hadolint, checkmake) via podman (same checks CI runs)
	podman run --rm -i docker.io/hadolint/hadolint < Containerfile
	podman run --rm --workdir / \
		-v $(CURDIR)/Makefile:/Makefile:z \
		-v $(CURDIR)/checkmake.ini:/checkmake.ini:z \
		quay.io/checkmake/checkmake:latest

run: build require-secret | $(WORK_DIR) $(DATA_DIR)   ## Launch opencode in the sandbox (default)
	podman run --name capsule $(RUN_FLAGS) $(IMAGE)

shell: build require-secret | $(WORK_DIR) $(DATA_DIR) ## Open a bash shell in the sandbox instead
	podman run $(RUN_FLAGS) $(IMAGE) bash

login:                            ## Store your OpenRouter API key in podman's secret store (prompts once)
	@printf 'Paste your OpenRouter API key (input hidden): '; \
	read -rs TOKEN; echo; \
	if [ -z "$$TOKEN" ]; then echo "No token entered; aborting."; exit 1; fi; \
	podman secret rm $(SECRET) >/dev/null 2>&1 || true; \
	printf '%s' "$$TOKEN" | podman secret create $(SECRET) - >/dev/null; \
	echo "Token stored as podman secret '$(SECRET)'."

logout:                           ## Remove the stored OpenRouter API key
	-podman secret rm $(SECRET)

build:                            ## Build the image
	podman build --build-arg UID=$(UID) --build-arg GID=$(GID) -t $(IMAGE) .

rebuild:                          ## Rebuild the image from scratch (no cache)
	podman build --no-cache --build-arg UID=$(UID) --build-arg GID=$(GID) -t $(IMAGE) .

clean:                            ## Remove the capsule image, then prune dangling images + build cache
	-podman rmi $(IMAGE)
	-podman image prune -f
	-podman builder prune -f

prune:                            ## Reclaim disk: drop dangling (untagged) images and stale build cache
	-podman image prune -f
	-podman builder prune -f

purge: clean logout               ## Full reset: image, dangling images, build cache, token AND your data dir
	-rm -rf $(CAPSULE_DIR)

where:                            ## Print the host data directory that is mounted
	@echo $(CAPSULE_DIR)

require-secret:
	@podman secret inspect $(SECRET) >/dev/null 2>&1 || \
		{ echo "No OpenRouter API key stored. Run 'make login' first."; exit 1; }

$(WORK_DIR) $(DATA_DIR):
	mkdir -p $@

help:                             ## List targets
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'
