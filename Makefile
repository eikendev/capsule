SHELL         := /bin/bash

IMAGE         ?= capsule
SECRET        ?= capsule-openrouter-key
XDG_DATA_HOME ?= $(HOME)/.local/share
CAPSULE_DIR   ?= $(XDG_DATA_HOME)/capsule
WORK_DIR      := $(CAPSULE_DIR)/work
OPENCODE_DIR  := $(CAPSULE_DIR)/.opencode-data
CLAUDE_DIR    := $(CAPSULE_DIR)/.claude-data
CLAUDE_JSON   := $(CAPSULE_DIR)/.claude.json
UID           := $(shell id -u)
GID           := $(shell id -g)

# Flags shared by every agent.
#   --userns=keep-id      map host UID into the container.
#   --cap-add=SYS_PTRACE  required by strace/ltrace/gdb; denied by default.
#   :z                    relabel bind mounts for SELinux.
COMMON_FLAGS = --rm -it --userns=keep-id \
	--cap-add=SYS_PTRACE \
	-v $(WORK_DIR):/work:z \
	-w /work

# OpenRouter key is mounted as a podman secret (tmpfs); opencode.json reads
# it via {file:...}.
OPENCODE_FLAGS = --secret $(SECRET) \
	-v $(OPENCODE_DIR):/home/dev/.local/share/opencode:z \
	$(COMMON_FLAGS)

# Claude Code splits its state in two: OAuth credentials live under
# ~/.claude/, but account and onboarding state live in the sibling file
# ~/.claude.json. Both must persist, or Claude Code treats each run as a
# fresh install and re-prompts for login.
CLAUDE_FLAGS = -v $(CLAUDE_DIR):/home/dev/.claude:z \
	-v $(CLAUDE_JSON):/home/dev/.claude.json:z \
	$(COMMON_FLAGS)

.DEFAULT_GOAL := opencode

.PHONY: test
test:                              ## Lint (hadolint, checkmake) via podman (same checks CI runs)
	podman run --rm -i docker.io/hadolint/hadolint < Containerfile
	podman run --rm --workdir / \
		-v $(CURDIR)/Makefile:/Makefile:z \
		-v $(CURDIR)/checkmake.ini:/checkmake.ini:z \
		quay.io/checkmake/checkmake:latest

.PHONY: opencode
opencode: build require-secret | $(WORK_DIR) $(OPENCODE_DIR) ## Launch opencode in the sandbox (default)
	podman run --name capsule $(OPENCODE_FLAGS) $(IMAGE)

.PHONY: claude
claude: build | $(WORK_DIR) $(CLAUDE_DIR) $(CLAUDE_JSON) $(CLAUDE_DIR)/settings.json ## Launch Claude Code in the sandbox
	podman run --name capsule-claude $(CLAUDE_FLAGS) $(IMAGE) claude

.PHONY: shell
shell: build | $(WORK_DIR) $(OPENCODE_DIR) $(CLAUDE_DIR) $(CLAUDE_JSON) ## Open a bash shell with both agents' data mounted
	podman run $(COMMON_FLAGS) \
		-v $(OPENCODE_DIR):/home/dev/.local/share/opencode:z \
		-v $(CLAUDE_DIR):/home/dev/.claude:z \
		-v $(CLAUDE_JSON):/home/dev/.claude.json:z \
		$(IMAGE) bash

.PHONY: login
login:                            ## Store your OpenRouter API key in podman's secret store (prompts once)
	@printf 'Paste your OpenRouter API key (input hidden): '; \
	read -rs TOKEN; echo; \
	if [ -z "$$TOKEN" ]; then echo "No token entered; aborting."; exit 1; fi; \
	podman secret rm $(SECRET) >/dev/null 2>&1 || true; \
	printf '%s' "$$TOKEN" | podman secret create $(SECRET) - >/dev/null; \
	echo "Token stored as podman secret '$(SECRET)'."

.PHONY: logout
logout:                           ## Remove the stored OpenRouter API key
	-podman secret rm $(SECRET)

.PHONY: build
build:                            ## Build the image
	podman build --build-arg UID=$(UID) --build-arg GID=$(GID) -t $(IMAGE) .

.PHONY: rebuild
rebuild:                          ## Rebuild the image from scratch (no cache)
	podman build --no-cache --build-arg UID=$(UID) --build-arg GID=$(GID) -t $(IMAGE) .

.PHONY: clean
clean:                            ## Remove the capsule image, then prune dangling images + build cache
	-podman rmi $(IMAGE)
	-podman image prune -f
	-podman builder prune -f

.PHONY: prune
prune:                            ## Reclaim disk: drop dangling (untagged) images and stale build cache
	-podman image prune -f
	-podman builder prune -f

.PHONY: purge
purge: clean logout               ## Full reset: image, dangling images, build cache, token AND your data dir
	-rm -rf $(CAPSULE_DIR)

.PHONY: where
where:                            ## Print the host data directory that is mounted
	@echo $(CAPSULE_DIR)

.PHONY: require-secret
require-secret:
	@podman secret inspect $(SECRET) >/dev/null 2>&1 || \
		{ echo "No OpenRouter API key stored. Run 'make login' first."; exit 1; }

# Podman requires bind-mount sources to exist before the container starts;
# it will not create them the way Docker does. These rules pre-create them.
$(WORK_DIR) $(OPENCODE_DIR) $(CLAUDE_DIR):
	mkdir -p $@

$(CLAUDE_JSON):
	@mkdir -p $(dir $@)
	touch $@

# Claude Code equivalent of opencode.json's "permission": "allow". Written
# once; won't overwrite a hand-edited file.
$(CLAUDE_DIR)/settings.json: | $(CLAUDE_DIR)
	printf '{\n  "permissions": {\n    "defaultMode": "bypassPermissions"\n  }\n}\n' > $@

.PHONY: help
help:                             ## List targets
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'
