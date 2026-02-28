# =============================================================================
# Claude Code in Docker — Sandboxed GitHub Workflow
# =============================================================================
# Usage:
#   docker build -t claude-code .
#   docker run -it --rm \
#     -e ANTHROPIC_API_KEY="sk-ant-..." \
#     -e GITHUB_TOKEN="ghp_..." \
#     -e GIT_USER_NAME="Your Name" \
#     -e GIT_USER_EMAIL="you@example.com" \
#     claude-code
# =============================================================================

FROM node:22-slim

# Install system dependencies (includes GPG for commit signing)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    openssh-client \
    build-essential \
    python3 \
    python3-pip \
    ripgrep \
    jq \
    vim \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install latest npm (security best practice)
RUN npm install -g npm@latest

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@latest

# Create non-root user for security
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /workspace /home/claude/.claude /home/claude/.gnupg && \
    chown -R claude:claude /workspace /home/claude && \
    chmod 700 /home/claude/.gnupg

# Switch to non-root user
USER claude
WORKDIR /workspace

# ── Credentials are passed at runtime via environment variables ──
# ANTHROPIC_API_KEY  — your Anthropic API key (required)
# GITHUB_TOKEN       — GitHub personal access token (required for push/PR)
# GIT_USER_NAME      — git commit author name
# GIT_USER_EMAIL     — git commit author email

# Copy the entrypoint script
COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

ENTRYPOINT ["/home/claude/entrypoint.sh"]
# Default: drop into interactive Claude Code session
CMD ["interactive"]
