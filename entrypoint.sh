#!/bin/bash
set -e

# ── Configure Git ──
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# Configure GitHub authentication via token
if [ -n "$GITHUB_TOKEN" ]; then
    git config --global credential.helper store
    echo "https://oauth2:${GITHUB_TOKEN}@github.com" > /home/claude/.git-credentials
    chmod 600 /home/claude/.git-credentials

    echo "$GITHUB_TOKEN" | git credential approve <<EOF
protocol=https
host=github.com
username=oauth2
password=$GITHUB_TOKEN
EOF
    echo "✓ GitHub credentials configured"
else
    echo "⚠ No GITHUB_TOKEN set — push/clone of private repos will fail"
fi

# ═══════════════════════════════════════════════════════════════════
# ── Commit Signing Setup ──
# Supports 3 methods (set SIGNING_METHOD env var):
#   1. "gpg"     — Import a GPG private key
#   2. "ssh"     — Use a mounted SSH key
#   3. "none"    — No signing
#   4. "auto"    — Auto-detect (default)
# ═══════════════════════════════════════════════════════════════════

SIGNING_METHOD="${SIGNING_METHOD:-auto}"

# Auto-detect signing method
if [ "$SIGNING_METHOD" = "auto" ]; then
    if [ -n "$GPG_PRIVATE_KEY" ] || [ -f /home/claude/.gnupg/private.key ]; then
        SIGNING_METHOD="gpg"
    elif [ -f /home/claude/.ssh/signing_key ] || [ -f /home/claude/.ssh/id_ed25519 ]; then
        SIGNING_METHOD="ssh"
    else
        SIGNING_METHOD="none"
    fi
fi

case "$SIGNING_METHOD" in
    gpg)
        echo "⟳ Setting up GPG commit signing..."

        # Import key from env var (base64-encoded) or from mounted file
        if [ -n "$GPG_PRIVATE_KEY" ]; then
            echo "$GPG_PRIVATE_KEY" | base64 -d | gpg --batch --import 2>/dev/null
        elif [ -f /home/claude/.gnupg/private.key ]; then
            gpg --batch --import /home/claude/.gnupg/private.key 2>/dev/null
        else
            echo "✗ ERROR: GPG signing requested but no key found"
            echo "  Either set GPG_PRIVATE_KEY (base64) or mount key to /home/claude/.gnupg/private.key"
            exit 1
        fi

        # If passphrase is provided, configure gpg-agent to cache it
        if [ -n "$GPG_PASSPHRASE" ]; then
            echo "allow-preset-passphrase" > /home/claude/.gnupg/gpg-agent.conf
            echo "default-cache-ttl 34560000" >> /home/claude/.gnupg/gpg-agent.conf
            echo "max-cache-ttl 34560000" >> /home/claude/.gnupg/gpg-agent.conf
            gpgconf --kill gpg-agent 2>/dev/null || true
            gpg-connect-agent /bye 2>/dev/null || true

            # Preset the passphrase for all keygrips
            GPG_KEYGRIPS=$(gpg --list-secret-keys --with-keygrip 2>/dev/null | grep Keygrip | awk '{print $3}')
            for KEYGRIP in $GPG_KEYGRIPS; do
                /usr/lib/gnupg/gpg-preset-passphrase --preset "$KEYGRIP" <<< "$GPG_PASSPHRASE" 2>/dev/null || true
            done
        else
            # No passphrase — configure for non-interactive use
            echo "no-tty" > /home/claude/.gnupg/gpg.conf
            echo "batch" >> /home/claude/.gnupg/gpg.conf
        fi

        # Determine signing key ID
        if [ -n "$GPG_KEY_ID" ]; then
            SIGN_KEY="$GPG_KEY_ID"
        else
            SIGN_KEY=$(gpg --list-secret-keys --keyid-format long 2>/dev/null \
                | grep -oP '(?<=\/)[A-F0-9]{16}' | head -1)
        fi

        if [ -z "$SIGN_KEY" ]; then
            echo "✗ ERROR: Could not determine GPG key ID"
            exit 1
        fi

        git config --global user.signingkey "$SIGN_KEY"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
        git config --global gpg.program gpg

        echo "✓ GPG signing configured (key: $SIGN_KEY)"
        ;;

    ssh)
        echo "⟳ Setting up SSH commit signing..."

        # Find the SSH key
        SSH_SIGN_KEY=""
        for keypath in /home/claude/.ssh/signing_key /home/claude/.ssh/id_ed25519 /home/claude/.ssh/id_rsa; do
            if [ -f "$keypath" ]; then
                SSH_SIGN_KEY="$keypath"
                break
            fi
        done

        if [ -z "$SSH_SIGN_KEY" ]; then
            echo "✗ ERROR: SSH signing requested but no key found"
            echo "  Mount your key to /home/claude/.ssh/signing_key"
            exit 1
        fi

        chmod 600 "$SSH_SIGN_KEY" 2>/dev/null || true

        # Create allowed_signers file (required by git for verification)
        if [ -n "$GIT_USER_EMAIL" ]; then
            SSH_PUB_KEY="${SSH_SIGN_KEY}.pub"
            if [ ! -f "$SSH_PUB_KEY" ]; then
                ssh-keygen -y -f "$SSH_SIGN_KEY" > "$SSH_PUB_KEY" 2>/dev/null || true
            fi
            if [ -f "$SSH_PUB_KEY" ]; then
                echo "$GIT_USER_EMAIL $(cat "$SSH_PUB_KEY")" > /home/claude/.ssh/allowed_signers
                git config --global gpg.ssh.allowedSignersFile /home/claude/.ssh/allowed_signers
            fi
        fi

        git config --global user.signingkey "$SSH_SIGN_KEY"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
        git config --global gpg.format ssh

        echo "✓ SSH signing configured (key: $SSH_SIGN_KEY)"
        ;;

    none)
        echo "⚠ Commit signing disabled"
        ;;
esac

# Verify Anthropic API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "✗ ERROR: ANTHROPIC_API_KEY is required"
    echo "  Pass it with: -e ANTHROPIC_API_KEY=sk-ant-..."
    exit 1
fi
echo "✓ Anthropic API key detected"

# ── Clone repo if GITHUB_REPO is set ──
if [ -n "$GITHUB_REPO" ]; then
    REPO_DIR="/workspace/$(basename "$GITHUB_REPO" .git)"
    if [ ! -d "$REPO_DIR/.git" ]; then
        echo "⟳ Cloning $GITHUB_REPO ..."
        git clone "https://oauth2:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" "$REPO_DIR"
    fi
    cd "$REPO_DIR"
    echo "✓ Working directory: $(pwd)"

    if [ -n "$GITHUB_BRANCH" ]; then
        git checkout "$GITHUB_BRANCH" 2>/dev/null || git checkout -b "$GITHUB_BRANCH"
        echo "✓ On branch: $GITHUB_BRANCH"
    fi
fi

# ── Run Claude Code ──
case "${1:-interactive}" in
    interactive)
        echo ""
        echo "═══════════════════════════════════════════════════"
        echo " Claude Code — Interactive Mode"
        echo " Signing: $SIGNING_METHOD"
        echo "═══════════════════════════════════════════════════"
        echo ""
        exec claude --dangerously-skip-permissions
        ;;
    headless)
        if [ -z "$CLAUDE_PROMPT" ]; then
            echo "✗ ERROR: CLAUDE_PROMPT is required in headless mode"
            exit 1
        fi
        echo "⟳ Running headless: $CLAUDE_PROMPT"
        exec claude -p "$CLAUDE_PROMPT" \
            --dangerously-skip-permissions \
            --output-format "${CLAUDE_OUTPUT_FORMAT:-text}"
        ;;
    bash)
        exec /bin/bash
        ;;
    *)
        exec claude "$@"
        ;;
esac
