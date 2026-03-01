---
name: jenkins-ops
description: Manage Jenkins CI/CD jobs — trigger, monitor, configure, and troubleshoot. Use for any Jenkins-related operation.
---

# Jenkins Operations Skill

> **Prerequisite**: `jenkins_ops.py` must be available in the project's `scripts/` directory
> or installed from this skill's `scripts/` folder.

## Architecture

```
┌─────────────────────┐      ssh user@localhost       ┌──────────────────┐
│  Jenkins (Docker)   │ ─────────────────────────▶   │   Host Machine    │
│  Scheduler only     │   all commands run here →    │  python/rsync/ssh │
│  --network host     │                              │  conda env, tools │
└─────────────────────┘                              └──────────────────┘
```

> **Core Principle**: Jenkins runs in Docker as scheduler only. All tasks execute via
> `ssh user@localhost` on the host machine. Never install python/rsync inside the container.

- **Default URL**: `http://localhost:8080`
- **Credentials**: Set via `JENKINS_URL`, `JENKINS_USER`, `JENKINS_PASS` env vars
- **Container**: `docker ps --filter name=jenkins`
- **Unified Interface**: `jenkins_ops.py` (CLI + Library)

## Setup

### 1. Copy the script to your project

```bash
cp /path/to/agent-skills/jenkins-ops/scripts/jenkins_ops.py your_project/scripts/
```

Or symlink:

```bash
ln -sf /path/to/agent-skills/jenkins-ops/scripts/jenkins_ops.py your_project/scripts/jenkins_ops.py
```

### 2. Environment variables (optional, defaults shown)

```bash
export JENKINS_URL="http://localhost:8080"
export JENKINS_USER="admin"
export JENKINS_PASS="admin123"
```

## CLI Quick Reference

```bash
# List all jobs
python3 scripts/jenkins_ops.py list

# Trigger build (async, returns immediately)
python3 scripts/jenkins_ops.py fire <job-name> [PARAM=VALUE ...]

# Trigger build (sync, streams console output)
python3 scripts/jenkins_ops.py trigger <job-name> [PARAM=VALUE ...]

# Check build status
python3 scripts/jenkins_ops.py status <job-name> [build-number]

# Get console log
python3 scripts/jenkins_ops.py log <job-name> [build-number]

# Create pipeline job from Jenkinsfile
python3 scripts/jenkins_ops.py create <job-path> --script <Jenkinsfile>

# Create folder
python3 scripts/jenkins_ops.py create-folder <name> [--parent <path>]

# Update job config
python3 scripts/jenkins_ops.py update <job-path> --script <Jenkinsfile>

# Delete job
python3 scripts/jenkins_ops.py delete <job-path>

# Cancel queued build
python3 scripts/jenkins_ops.py cancel <queue-id>

# Reload configuration
python3 scripts/jenkins_ops.py reload
```

## Library Mode (for Python scripts / MCP)

```python
from jenkins_ops import JenkinsOps
ops = JenkinsOps()

# Health check
ops.is_available()

# Trigger + wait
result = ops.trigger("sdk-release", params={"DEPLOY_CK": "true"})
print(result["success"], result["build_number"])

# Async trigger
result = ops.fire("market-data-sync", params={"START_DATE": "20260210"})
print(result["queue_id"])

# Job lifecycle
ops.create_folder("my_folder")
ops.create_pipeline("my_folder/build", script_path="/path/to/Jenkinsfile")
ops.update_config("my_folder/build", script_path="/new/Jenkinsfile")
ops.delete_job("my_folder/build")

# Auto-provision project jobs
ops.ensure_project_jobs("devloop", "my_project", {
    "build": "/path/to/Jenkinsfile.build",
    "run": "/path/to/Jenkinsfile.run",
})
```

## Pipeline Pattern

All pipelines should use the SSH-to-host pattern:

```groovy
pipeline {
    agent any
    environment {
        SSH = 'ssh -o StrictHostKeyChecking=no -o BatchMode=yes user@localhost'
    }
    stages {
        stage('Example') {
            steps {
                sh "${SSH} bash /path/to/your/script.sh"
            }
        }
    }
}
```

> ⚠️ **Key Notes**:
>
> - Non-interactive SSH doesn't load `.bashrc` — use full python paths
> - Use host absolute paths, not `/workspace/...`
> - Commands with complex quoting must be wrapped in script files
> - No `\` line continuations in Groovy `sh` strings (XML compression breaks them)

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Jenkins unresponsive | `docker ps --filter name=jenkins` / `docker restart jenkins` |
| Builds queued | Check executor count, stuck builds, `disableConcurrentBuilds` |
| `python3: not found` | Use full path (e.g., `/home/user/miniconda3/bin/python3`) in pipeline |
| Groovy parse error | Don't use `\` line continuation in `sh` — use single line or external script |
| Container rebuilt, packages gone | Normal — all commands run on host via SSH, not in container |

## Rules

1. **Jenkins = Scheduler Only**: All commands execute on host via SSH
2. **jenkins_ops.py only**: All Jenkins operations go through the unified script
3. **Absolute paths**: Scripts use host absolute paths, not container paths
4. **Audit trail**: Use Jenkins for all periodic/CI tasks to maintain audit history
