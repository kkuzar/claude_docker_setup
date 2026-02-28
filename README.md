# Claude Code in Docker — Sandboxed GitHub Workflow

Run Claude Code inside a Docker container for full isolation. Claude can clone, edit, commit (with optional signed commits), and push to your GitHub repos without touching your host machine.

## Quick Start

```bash
# 1. Copy and fill in your credentials
cp env.example .env
# Edit .env with your ANTHROPIC_API_KEY and GITHUB_TOKEN

# 2. Run with the language profile you need
docker compose run --rm claude-golang      # Go
docker compose run --rm claude-rust        # Rust
docker compose run --rm claude-python      # Python
docker compose run --rm claude-javascript  # JavaScript / TypeScript
docker compose run --rm claude             # All languages (default)
```

## Language Profiles

Each profile includes a full base toolset (git, gcc/g++/make, curl, wget, vim, ripgrep, jq, zip/unzip) plus the language-specific toolchain.

| Service | Toolchain added |
|---|---|
| `claude` | All of the below |
| `claude-golang` | Go (official tarball, latest stable) |
| `claude-rust` | Rust via rustup (stable) |
| `claude-python` | python3-dev, venv, pipx |
| `claude-javascript` | TypeScript, ts-node, eslint, prettier |
| `claude-local` | All languages — mounts a local folder instead of cloning |

### Pinning the Go version

```bash
# In docker-compose.yml, under the golang/all build section:
docker compose build --build-arg GO_VERSION=1.22.3 claude-golang
```

## Working with Local Code

Use `claude-local` to work on a project already on your machine:

```bash
# In your .env:
LOCAL_PATH=../my-existing-project

docker compose run --rm claude-local
```

If `LOCAL_PATH` is not set, it defaults to `./workspace`.

## How Credentials Are Passed

| Variable | Purpose | Where to get it |
|---|---|---|
| `ANTHROPIC_API_KEY` | Authenticates with Anthropic API | [console.anthropic.com](https://console.anthropic.com/) |
| `GITHUB_TOKEN` | HTTPS auth for git clone/push | [github.com/settings/tokens](https://github.com/settings/tokens) — `repo` scope |
| `GIT_USER_NAME` | Git commit author name | Your name |
| `GIT_USER_EMAIL` | Git commit author email | Your email |

**Credentials are NEVER baked into the image.** They're injected at runtime via `.env`.

---

## Commit Signing

The entrypoint auto-detects your signing method, or you can set `SIGNING_METHOD` to `gpg`, `ssh`, or `none`.

### Option A: GPG Signing via Environment Variable (simplest)

```bash
# Export your GPG key as base64
gpg --export-secret-keys YOUR_KEY_ID | base64 -w0 > /tmp/gpg_b64.txt

# Add to .env
GPG_PRIVATE_KEY=$(cat /tmp/gpg_b64.txt)
GPG_PASSPHRASE=your-passphrase
```

### Option B: GPG Signing via Mounted Key File

```bash
gpg --export-secret-keys --armor YOUR_KEY_ID > ~/my-gpg-key.asc

docker compose run --rm \
  -v ~/my-gpg-key.asc:/home/claude/.gnupg/private.key:ro \
  claude
```

### Option C: SSH Signing (simpler, Git 2.34+)

```bash
# In docker-compose.yml, add to volumes:
# - ~/.ssh/id_ed25519:/home/claude/.ssh/signing_key:ro
```

> **Important**: Your SSH signing key must also be added to your GitHub account under
> Settings → SSH and GPG keys → "New SSH key" with type **Signing Key**.

---

## Usage Modes

### Interactive (default)

```bash
docker compose run --rm claude
```

### Auto-Clone a Repo

```bash
# In .env:
GITHUB_REPO=your-username/your-repo
GITHUB_BRANCH=feature/my-fix

docker compose run --rm claude-golang
```

### Headless (CI/CD)

```bash
docker compose run --rm \
  -e GITHUB_REPO="your-username/your-repo" \
  -e CLAUDE_PROMPT="Fix all lint errors and commit" \
  claude headless
```

### Debug Shell

```bash
docker compose run --rm claude bash
```

---

## Security Notes

- Container runs as **non-root user** (`claude`)
- `--dangerously-skip-permissions` is on because the container IS the sandbox
- GPG keys and passphrases exist only in container memory at runtime
- Use fine-grained GitHub tokens scoped to specific repos when possible

## GitHub Token Scopes

**Classic PAT**: select `repo`

**Fine-grained token**: Repository access → specific repos, Permissions → Contents (R/W), Pull requests (R/W)

## Troubleshooting

| Problem | Solution |
|---|---|
| `GPG signing failed` | Run with `bash` mode, then `gpg --list-secret-keys` |
| `error: gpg failed to sign the data` | Set `GPG_PASSPHRASE` or use a key without one |
| Commits not showing "Verified" on GitHub | Upload your GPG public key to GitHub Settings → SSH and GPG keys |
| SSH signing fails | Ensure key is mounted with correct permissions (`:ro` is fine) |
| `ERROR: ANTHROPIC_API_KEY is required` | Set it in `.env` |
| Go version too old | Build with `--build-arg GO_VERSION=x.y.z` |
