---
name: deploy-docs
description: "Build Sphinx HTML/PDF documentation and deploy to a remote server via rsync + nginx. Trigger: '发布文档', 'deploy docs', 'publish docs', '部署文档'."
---

# Deploy Docs

> **ROLE**: AG builds Sphinx docs locally, transfers them to a remote server, and configures nginx to serve them. AG does NOT modify doc content — only builds and deploys.

## Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{project_dir}` | Project root with `docs/` subdirectory | `/home/lgj/git/invest/crypto/quant_trading` |
| `{server}` | Remote server SSH host (IP or alias) | `8.152.216.242` |
| `{ssh_key}` | SSH identity file | `~/.ssh/id_ed25519` |
| `{ssh_user}` | SSH login user | `root` |
| `{deploy_path}` | Remote directory for docs | `/var/www/quant-docs` |
| `{port}` | Nginx listen port | `8003` |

## Operational Workflow

### Phase 1: Build Docs Locally

```bash
cd {project_dir}/docs && rm -rf _build/html && make html 2>&1 | tail -5
```

**Expected**: `build succeeded.` + `The HTML pages are in _build/html.`

For PDF (optional):

```bash
cd {project_dir}/docs && rm -rf _build/latex && make latexpdf LATEXMKOPTS="-f" 2>&1 | tail -5
```

### Phase 2: Self-Verify Build

Run a verification script to confirm all API pages have entries and no forbidden strings:

```bash
python3 /tmp/check_docs.py
```

If no check script exists, create one that:
1. Scans each `api/*.html` for `class="sig-name descname"` entries
2. Checks for forbidden strings (internal class names, `_modules/` links)
3. Reports entry count + CLEAN/LEAK status per page

**Gate**: ALL pages must be CLEAN with non-zero entries before deploying.

### Phase 3: Deploy to Server

#### 3a. Verify SSH Access

```bash
ssh -o ConnectTimeout=10 -i {ssh_key} {ssh_user}@{server} "echo SSH_OK && which nginx && which rsync"
```

**If nginx missing**:

```bash
ssh -i {ssh_key} {ssh_user}@{server} "yum install -y nginx && systemctl enable nginx && systemctl start nginx"
```

**If rsync missing**:

```bash
ssh -i {ssh_key} {ssh_user}@{server} "yum install -y rsync"
```

#### 3b. Create Remote Directory + Rsync

```bash
ssh -i {ssh_key} {ssh_user}@{server} "mkdir -p {deploy_path}"
rsync -avz --delete -e "ssh -i {ssh_key}" {project_dir}/docs/_build/html/ {ssh_user}@{server}:{deploy_path}/ 2>&1 | tail -3
```

**Expected**: `sent X bytes ... total size is Y ... speedup is Z`

#### 3c. Configure Nginx

Write the nginx config via `write_to_file` to a local temp file, then `scp` it to the server. **NEVER** use `ssh heredoc` or `send-keys` for multi-line file content — escaping `$uri` always breaks.

Create `/tmp/quant-docs-nginx.conf` locally:

```nginx
server {
    listen {port};
    server_name _;
    root {deploy_path};
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
}
```

Then deploy:

```bash
scp -i {ssh_key} /tmp/quant-docs-nginx.conf {ssh_user}@{server}:/etc/nginx/conf.d/quant-docs.conf
ssh -i {ssh_key} {ssh_user}@{server} "nginx -t 2>&1 && systemctl reload nginx && echo NGINX_OK"
```

### Phase 4: Verify Public Access

```bash
curl -s -o /dev/null -w "%{http_code}" http://{server}:{port}/ && echo " OK"
```

**Expected**: `200 OK`

**If 000 (connection refused)**: The cloud security group / firewall does not allow port `{port}`. Tell the user to add an inbound TCP rule for port `{port}` in the cloud console.

### Phase 5: Report

Report to user:
- Build status (warnings count)
- Self-verification results (entries per page)
- Deploy URL: `http://{server}:{port}/`

## Mandatory Rules

1. **ALWAYS self-verify before deploying.** Never rsync docs that haven't passed the check script.
2. **NEVER use SSH heredoc/send-keys for nginx config.** Write the file locally with `write_to_file`, then `scp` to the server. `$uri` escaping through SSH + bash + tmux is impossible to get right.
3. **ALWAYS use `--delete` with rsync.** Stale files from previous builds must be removed.
4. **ALWAYS verify physical artifact** (`curl` the live URL) before reporting success.
5. **Use `-i {ssh_key}`** on every SSH/SCP/rsync command. Don't rely on ssh-agent.

## Anti-Patterns

❌ Deploying without self-verification
   → Run check_docs.py first. Empty API pages = broken docs in production

❌ Using `ssh "cat > file << EOF ... $uri ... EOF"` to write nginx config
   → `$uri` gets expanded/mangled. Use `scp` from a local file instead

❌ Forgetting `mkdir -p` before rsync
   → rsync does NOT create parent directories on the remote

❌ Using port 80 without checking security group
   → Most cloud instances block port 80 by default. Ask user which port

❌ Reporting "deployed" before `curl` verification
   → Security groups, firewall, SELinux can all block access silently

## Troubleshooting

| Problem | Fix |
|---------|-----|
| SSH asks for password | Key not bound to instance. Bind via cloud console + reboot instance |
| `Connection closed by remote host` | Instance is rebooting. Wait 30-60s and retry |
| rsync: `command not found` | Install rsync on remote: `yum install -y rsync` |
| rsync: `mkdir failed` | Create directory first: `ssh ... "mkdir -p {deploy_path}"` |
| nginx `try_files` shows `\\` instead of `$uri` | Config was written via SSH heredoc. Rewrite via `scp` from local file |
| curl returns `000` | Port not open in cloud security group. Ask user to add inbound rule |
| curl returns `403` | Check `ls -la {deploy_path}/` — files may have wrong permissions. `chmod -R 755` |
| nginx conflicting `server_name` warning | Default `/etc/nginx/nginx.conf` also uses `server_name _`. Safe to ignore if using a custom port |

## Default Server Configuration

For the QuantTrading project:

| Variable | Value |
|----------|-------|
| `{project_dir}` | `/home/lgj/git/invest/crypto/quant_trading` |
| `{server}` | `8.152.216.242` |
| `{ssh_key}` | `~/.ssh/id_ed25519` |
| `{ssh_user}` | `root` |
| `{deploy_path}` | `/var/www/quant-docs` |
| `{port}` | `8003` |
| Live URL | `http://8.152.216.242:8003/` |
