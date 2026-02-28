# Claude Code in Docker — Sandboxed GitHub Workflow with Commit Signing

Run Claude Code inside a Docker container for full isolation. Claude can clone, edit, commit (with signed commits), and push to your GitHub repos without touching your host machine.

## Quick Start

```bash
# 1. Copy and fill in your credentials
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY and GITHUB_TOKEN

# 2. Build the image
docker build -t claude-code .

# 3. Run interactively
docker run -it --rm --env-file .env claude-code
```

## How Credentials Are Passed

| Variable | Purpose | Where to get it |
|---|---|---|
| `ANTHROPIC_API_KEY` | Authenticates with Anthropic API | [console.anthropic.com](https://console.anthropic.com/) |
| `GITHUB_TOKEN` | HTTPS auth for git clone/push | [github.com/settings/tokens](https://github.com/settings/tokens) — `repo` scope |
| `GIT_USER_NAME` | Git commit author name | Your name |
| `GIT_USER_EMAIL` | Git commit author email | Your email |

**Credentials are NEVER baked into the image.** They're injected at runtime.

---

## Commit Signing

The entrypoint auto-detects your signing method, or you can set `SIGNING_METHOD` to `gpg`, `ssh`, or `none`.

### Option A: GPG Signing via Environment Variable (simplest)

Export your GPG key as base64 and pass it in:

```bash
# On your host — export the key
gpg --export-secret-keys YOUR_KEY_ID | base64 -w0 > /tmp/gpg_b64.txt

# Run with the key
docker run -it --rm --env-file .env \
  -e GPG_PRIVATE_KEY="$(cat /tmp/gpg_b64.txt)" \
  -e GPG_PASSPHRASE="your-passphrase" \
  claude-code
```

### Option B: GPG Signing via Mounted Key File

```bash
# Export key to a file
gpg --export-secret-keys --armor YOUR_KEY_ID > ~/my-gpg-key.asc

docker run -it --rm --env-file .env \
  -v ~/my-gpg-key.asc:/home/claude/.gnupg/private.key:ro \
  -e GPG_PASSPHRASE="your-passphrase" \
  claude-code
```

### Option C: SSH Signing (simpler, Git 2.34+)

Mount your SSH private key:

```bash
docker run -it --rm --env-file .env \
  -v ~/.ssh/id_ed25519:/home/claude/.ssh/signing_key:ro \
  claude-code
```

> **Important**: Your SSH signing key must also be added to your GitHub account under
> Settings → SSH and GPG keys → "New SSH key" with type **Signing Key**.

### Verifying It Works

Inside the container, run:

```bash
# For GPG
gpg --list-secret-keys --keyid-format long
git log --show-signature -1

# For SSH
git log --show-signature -1
```

On GitHub, signed commits show a green "Verified" badge.

---

## Usage Modes

### Interactive (default)
```bash
docker run -it --rm --env-file .env claude-code
```

### Auto-Clone a Repo
```bash
docker run -it --rm --env-file .env \
  -e GITHUB_REPO="your-username/your-repo" \
  -e GITHUB_BRANCH="feature/my-fix" \
  claude-code
```

### Headless (CI/CD)
```bash
docker run --rm --env-file .env \
  -e GITHUB_REPO="your-username/your-repo" \
  -e CLAUDE_PROMPT="Fix all lint errors and commit" \
  claude-code headless
```

### Mount Local Folder
```bash
docker run -it --rm --env-file .env \
  -v $(pwd)/my-project:/workspace/my-project \
  -w /workspace/my-project \
  claude-code
```

### Debug Shell
```bash
docker run -it --rm --env-file .env claude-code bash
```

---

## Full Example: GPG-Signed Commits on a GitHub Repo

```bash
docker run -it --rm \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -e GITHUB_TOKEN="ghp_..." \
  -e GIT_USER_NAME="Jane Doe" \
  -e GIT_USER_EMAIL="jane@example.com" \
  -e GITHUB_REPO="jane/my-project" \
  -e GITHUB_BRANCH="claude/refactor" \
  -e GPG_PRIVATE_KEY="$(gpg --export-secret-keys ABCD1234 | base64 -w0)" \
  -e GPG_PASSPHRASE="hunter2" \
  claude-code
```

Claude Code will clone the repo, check out the branch, and every commit it makes will be GPG-signed.

---

## Security Notes

- Container runs as **non-root user** (`claude`)
- `--dangerously-skip-permissions` is on because the container IS the sandbox
- GPG keys and passphrases exist only in container memory at runtime
- Add `--read-only --tmpfs /tmp` for extra hardening
- Use fine-grained GitHub tokens scoped to specific repos when possible

## GitHub Token Scopes

**Classic PAT**: select `repo`

**Fine-grained token**: Repository access → specific repos, Permissions → Contents (R/W), Pull requests (R/W)

## Troubleshooting

| Problem | Solution |
|---|---|
| `GPG signing failed` | Check key import: run with `bash` mode, then `gpg --list-secret-keys` |
| `error: gpg failed to sign the data` | Passphrase issue — set `GPG_PASSPHRASE` or use a key without one |
| Commits not showing "Verified" on GitHub | Upload your GPG public key to GitHub Settings → SSH and GPG keys |
| SSH signing fails | Ensure key is mounted with correct permissions (`:ro` is fine) |
| `ERROR: ANTHROPIC_API_KEY is required` | Set it in `.env` or pass `-e` |
