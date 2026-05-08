# Agent container: opencode (Bun-based) + pipelock (Go binary) on PATH.
#
# Two-stage build so the final image doesn't carry the Go toolchain:
#   stage 1: build pipelock from source
#   stage 2: copy the static binary into the bun runtime image
#
# Pin versions explicitly. Floating tags are how you wake up to a broken
# build six months from now.

# ----- stage 1: build pipelock --------------------------------------------
FROM golang:1.24-alpine AS pipelock-builder

# git is needed by `go install` to resolve module sources.
RUN apk add --no-cache git ca-certificates

# Pin pipelock to a release tag. Bump deliberately, not by accident.
# See https://github.com/luckyPipewrench/pipelock/releases
ARG PIPELOCK_VERSION=v0.1.4

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOFLAGS=-trimpath

RUN go install "github.com/luckyPipewrench/pipelock/cmd/pipelock@${PIPELOCK_VERSION}"

# ----- stage 2: runtime ---------------------------------------------------
FROM oven/bun:1-debian

# Pin opencode the same way. Use `latest` only if you genuinely want
# unattended upgrades on every rebuild.
ARG OPENCODE_VERSION=latest

# Runtime deps:
#   - ca-certificates: for HTTPS to opencode.ai zen, github, etc.
#   - git:             opencode + npm packages routinely shell out to git
#   - nodejs/npm:      MCP servers shipped via `npx` need a node runtime;
#                      bun's npx shim doesn't cover all of them
#   - curl, jq:        AGENTS.md tells the model to use these for the
#                      pipelock fetch endpoint
#   - openssh-client:  git over ssh, if you mount an ssh key in
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        nodejs \
        npm \
        curl \
        jq \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Bring in the pipelock binary from the builder stage.
COPY --from=pipelock-builder /go/bin/pipelock /usr/local/bin/pipelock

# Sanity check at build time. If this fails the image fails — better than
# discovering it the first time the agent tries to launch an MCP server.
RUN bun install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm install -g @modelcontextprotocol/server-filesystem \
    && pipelock version \
    && opencode --version

# Pipelock config lives at a stable path. The compose file mounts the same
# pipelock.yaml here read-only so the agent and the pipelock container
# share one source of truth.
RUN mkdir -p /etc/pipelock /workspace /root/.config/opencode

WORKDIR /workspace

# No ENTRYPOINT — docker-compose's `command:` decides what runs. Default
# to a shell so `docker compose run --rm agent` drops you in.
CMD ["sh"]
