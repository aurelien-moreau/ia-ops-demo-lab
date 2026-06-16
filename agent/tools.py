"""Tool implementations for the AI Ops Agent."""

import json
import os
import subprocess
import time
from pathlib import Path

# ARGO_REPO points to the local clone of ia-ops-argo-app (the GitOps repo ArgoCD watches).
# Default: ../ia-ops-argo-app relative to this file's parent directory.
_default_argo = Path(__file__).parent.parent.parent / "ia-ops-argo-app"
REPO_PATH = os.environ.get("ARGO_REPO", str(_default_argo))

TOOLS = [
    {
        "name": "get_cluster_status",
        "description": "Get an overview of all pods and deployments in the cluster namespace. Use this first to identify what's broken.",
        "input_schema": {
            "type": "object",
            "properties": {
                "namespace": {
                    "type": "string",
                    "description": "Kubernetes namespace to inspect",
                    "default": "default",
                },
            },
        },
    },
    {
        "name": "get_pod_logs",
        "description": "Get recent logs from a specific pod. Essential for understanding why a pod is crashing.",
        "input_schema": {
            "type": "object",
            "properties": {
                "pod_name": {
                    "type": "string",
                    "description": "Full name of the pod (e.g. demo-app-7d9f8b-xk2pl)",
                },
                "namespace": {
                    "type": "string",
                    "description": "Kubernetes namespace",
                    "default": "default",
                },
                "previous": {
                    "type": "boolean",
                    "description": "Get logs from previous container instance (useful for CrashLoopBackOff)",
                    "default": True,
                },
                "lines": {
                    "type": "integer",
                    "description": "Number of log lines to retrieve",
                    "default": 50,
                },
            },
            "required": ["pod_name"],
        },
    },
    {
        "name": "describe_pod",
        "description": "Describe a Kubernetes pod to get its events, status details, and environment configuration. Very useful for diagnosing configuration issues.",
        "input_schema": {
            "type": "object",
            "properties": {
                "pod_name": {
                    "type": "string",
                    "description": "Full name of the pod",
                },
                "namespace": {
                    "type": "string",
                    "description": "Kubernetes namespace",
                    "default": "default",
                },
            },
            "required": ["pod_name"],
        },
    },
    {
        "name": "read_manifest",
        "description": "Read a manifest file from the Git repository (source of truth for GitOps). Use this to inspect current configuration before applying a fix.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path to the file in the git repo (e.g. apps/demo-app/k8s/configmap.yaml)",
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "apply_fix",
        "description": "Apply a fix to the Git repository by writing corrected file content, then committing and pushing. ArgoCD will automatically pick up the change and sync the cluster.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path to the file to fix (e.g. apps/demo-app/k8s/configmap.yaml)",
                },
                "content": {
                    "type": "string",
                    "description": "The complete corrected content of the file",
                },
                "commit_message": {
                    "type": "string",
                    "description": "Git commit message describing the fix",
                },
            },
            "required": ["path", "content", "commit_message"],
        },
    },
    {
        "name": "force_argocd_sync",
        "description": "Force ArgoCD to immediately sync an application from Git instead of waiting for the 30s poll interval. Call this right after apply_fix to accelerate deployment.",
        "input_schema": {
            "type": "object",
            "properties": {
                "app_name": {
                    "type": "string",
                    "description": "ArgoCD application name",
                    "default": "demo-app",
                },
            },
        },
    },
    {
        "name": "check_argocd_sync",
        "description": "Check the ArgoCD sync status of an application to see if the fix has been applied.",
        "input_schema": {
            "type": "object",
            "properties": {
                "app_name": {
                    "type": "string",
                    "description": "ArgoCD application name",
                    "default": "demo-app",
                },
            },
        },
    },
    {
        "name": "wait_for_healthy",
        "description": "Wait for all pods of an application to become healthy (Running state). Use this after applying a fix to confirm recovery.",
        "input_schema": {
            "type": "object",
            "properties": {
                "label_selector": {
                    "type": "string",
                    "description": "Kubernetes label selector (e.g. app=demo-app)",
                    "default": "app=demo-app",
                },
                "namespace": {
                    "type": "string",
                    "description": "Kubernetes namespace",
                    "default": "default",
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": "Max seconds to wait",
                    "default": 120,
                },
            },
        },
    },
]


def _run(cmd: list[str], timeout: int = 30) -> str:
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = result.stdout.strip()
        if result.returncode != 0 and result.stderr:
            output += f"\nSTDERR: {result.stderr.strip()}"
        return output or "(no output)"
    except subprocess.TimeoutExpired:
        return f"Command timed out after {timeout}s"
    except FileNotFoundError:
        return f"Command not found: {cmd[0]}"


def get_cluster_status(namespace: str = "default") -> str:
    pods = _run(["kubectl", "get", "pods", "-n", namespace, "-o", "wide"])
    deploys = _run(["kubectl", "get", "deployments", "-n", namespace])
    return f"=== PODS ===\n{pods}\n\n=== DEPLOYMENTS ===\n{deploys}"


def get_pod_logs(
    pod_name: str,
    namespace: str = "default",
    previous: bool = True,
    lines: int = 50,
) -> str:
    cmd = ["kubectl", "logs", pod_name, "-n", namespace, f"--tail={lines}"]
    if previous:
        cmd.append("--previous")
    result = _run(cmd)
    if "previous terminated container" in result.lower() or "not found" in result.lower():
        # Try without --previous flag
        cmd_no_prev = [c for c in cmd if c != "--previous"]
        result = _run(cmd_no_prev)
    return result


def describe_pod(pod_name: str, namespace: str = "default") -> str:
    return _run(["kubectl", "describe", "pod", pod_name, "-n", namespace])


def read_manifest(path: str) -> str:
    full_path = Path(REPO_PATH) / path
    if not full_path.exists():
        return f"File not found: {path}"
    return full_path.read_text()


def apply_fix(path: str, content: str, commit_message: str) -> str:
    full_path = Path(REPO_PATH) / path
    if not full_path.parent.exists():
        return f"Directory does not exist: {full_path.parent}"

    full_path.write_text(content)

    git_add = _run(["git", "-C", REPO_PATH, "add", path])
    git_commit = _run(
        ["git", "-C", REPO_PATH, "commit", "-m", commit_message]
    )
    git_push = _run(["git", "-C", REPO_PATH, "push"], timeout=15)

    return f"✓ File written\n✓ Git add: {git_add}\n✓ Git commit: {git_commit}\n✓ Git push: {git_push}"


def force_argocd_sync(app_name: str = "demo-app") -> str:
    # Annotate the Application to trigger an immediate hard refresh from Git.
    # ArgoCD picks up the annotation within ~1s and re-syncs without waiting for the 30s poll.
    refresh = _run([
        "kubectl", "annotate", "application", app_name,
        "-n", "argocd",
        "argocd.argoproj.io/refresh=hard",
        "--overwrite",
    ])
    time.sleep(3)  # let ArgoCD process the annotation and start syncing
    status = _run([
        "kubectl", "get", "application", app_name,
        "-n", "argocd",
        "-o", "jsonpath={.status.sync.status} {.status.health.status}",
    ])
    return f"✓ Hard refresh triggered for '{app_name}'\n{refresh}\nStatus: {status}"


def check_argocd_sync(app_name: str = "demo-app") -> str:
    result = _run(
        ["kubectl", "get", "application", app_name, "-n", "argocd", "-o", "jsonpath={.status.sync.status} {.status.health.status}"]
    )
    return f"ArgoCD status for '{app_name}': {result}"


def wait_for_healthy(
    label_selector: str = "app=demo-app",
    namespace: str = "default",
    timeout_seconds: int = 120,
) -> str:
    start = time.time()
    while time.time() - start < timeout_seconds:
        result = _run(
            ["kubectl", "get", "pods", "-n", namespace, "-l", label_selector, "--no-headers"]
        )
        lines = [l for l in result.splitlines() if l.strip()]
        if lines and all("Running" in l for l in lines):
            return f"✓ All pods are healthy:\n{result}"
        time.sleep(5)
    return f"⚠ Timeout after {timeout_seconds}s. Current state:\n{result}"


def execute_tool(name: str, inputs: dict) -> str:
    handlers = {
        "get_cluster_status": get_cluster_status,
        "get_pod_logs": get_pod_logs,
        "describe_pod": describe_pod,
        "read_manifest": read_manifest,
        "apply_fix": apply_fix,
        "force_argocd_sync": force_argocd_sync,
        "check_argocd_sync": check_argocd_sync,
        "wait_for_healthy": wait_for_healthy,
    }
    handler = handlers.get(name)
    if not handler:
        return f"Unknown tool: {name}"
    return handler(**inputs)
