# =============================================================================
# Claude Code in Docker — Multi-language Profiles
# =============================================================================
# Build targets (select via docker-compose service or --target flag):
#
#   base         — Common tools only (no language toolchain)
#   golang       — Go (official tarball, arch-aware)
#   rust         — Rust (rustup, stable)
#   python       — Python dev tools (venv, pipx, python3-dev)
#   javascript   — TypeScript / Node.js ecosystem
#   all          — All languages above (default)
# =============================================================================

# ─── Base: system tools + Claude Code ─────────────────────────────────────────
FROM node:22-slim AS base

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    openssh-client \
    build-essential \
    python3 \
    python3-pip \
    ripgrep \
    jq \
    vim \
    gnupg \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g npm@latest
RUN npm install -g @anthropic-ai/claude-code@latest

RUN useradd -m -s /bin/bash claude && \
    mkdir -p /workspace /home/claude/.claude /home/claude/.gnupg && \
    chown -R claude:claude /workspace /home/claude && \
    chmod 700 /home/claude/.gnupg

COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

USER claude
WORKDIR /workspace

ENTRYPOINT ["/home/claude/entrypoint.sh"]
CMD ["interactive"]

# ─── Go ───────────────────────────────────────────────────────────────────────
FROM base AS golang

USER root
ARG GO_VERSION=1.23.5
RUN ARCH=$(dpkg --print-architecture) && \
    GOARCH=$([ "$ARCH" = "arm64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" \
    | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"
USER claude

# ─── Rust ─────────────────────────────────────────────────────────────────────
FROM base AS rust

# runs as claude (inherited from base) — rustup installs to ~/.cargo
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path
ENV PATH="/home/claude/.cargo/bin:${PATH}"

# ─── Python ───────────────────────────────────────────────────────────────────
FROM base AS python

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-dev \
    python3-venv \
    pipx \
    && rm -rf /var/lib/apt/lists/*
USER claude

# ─── JavaScript / TypeScript ──────────────────────────────────────────────────
FROM base AS javascript

USER root
RUN npm install -g typescript ts-node @types/node eslint prettier
USER claude

# ─── All languages ────────────────────────────────────────────────────────────
FROM base AS all

USER root
ARG GO_VERSION=1.23.5
RUN ARCH=$(dpkg --print-architecture) && \
    GOARCH=$([ "$ARCH" = "arm64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" \
    | tar -C /usr/local -xz
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-dev \
    python3-venv \
    pipx \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g typescript ts-node @types/node eslint prettier
USER claude
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path
ENV PATH="/usr/local/go/bin:/home/claude/.cargo/bin:${PATH}"
