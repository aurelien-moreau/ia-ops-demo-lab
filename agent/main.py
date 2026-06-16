#!/usr/bin/env python3
"""
AI Ops Agent — Autonomous incident responder for Kubernetes/GitOps stacks.

Demo scenario: App enters CrashLoopBackOff due to misconfiguration.
The agent detects, investigates, fixes via Git, and confirms recovery.
"""

import os
import sys
import time
from datetime import datetime

import anthropic
from rich.console import Console
from rich.panel import Panel
from rich.rule import Rule
from rich.syntax import Syntax
from rich.text import Text

from tools import TOOLS, execute_tool

MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-4-6")
console = Console()

SYSTEM_PROMPT = """\
You are an elite SRE (Site Reliability Engineer) AI agent, expert in Kubernetes and GitOps operations.

## Your Mission
Autonomously detect and resolve production incidents in a Kubernetes cluster managed with ArgoCD and GitOps.

## Operating Principles
1. **Investigate first, fix second** — never guess. Read the actual error messages.
2. **GitOps is the source of truth** — all fixes MUST go through the Git repository, never `kubectl apply` directly.
3. **Be transparent** — explain what you find and what you're doing in clear language the team can follow.
4. **Confirm recovery** — after applying a fix, wait and verify the application is actually healthy.

## GitOps Repository Structure (ia-ops-argo-app)

```
apps/
  demo-app/k8s/
    configmap.yaml
    deployment.yaml
    service.yaml
  postgres/k8s/
    deployment.yaml
    service.yaml
```


## Workflow
1. `get_cluster_status` — identify which pods/deployments are unhealthy
2. `get_pod_logs` with `previous=False` — read the current logs to find the error
3. `read_manifest` — read the broken config or manifest before touching anything
4. `apply_fix` — write the corrected file, commit, and push to Git
5. `force_argocd_sync(app_name=<affected-app>)` — MANDATORY after every fix, skips the 30s poll wait
   - Fix on demo-app (configmap) → `force_argocd_sync(app_name="demo-app")`
   - Fix on postgres (deployment) → `force_argocd_sync(app_name="postgres")`
6. `check_argocd_sync(app_name=<affected-app>)` — confirm sync status for the same app
7. `wait_for_healthy` — confirm all demo-app pods are Running
8. Report a clear incident summary with root cause and fix applied.


The cluster namespace is 'default'.
The healthy DATABASE_URL format is: postgres://user:password@host:port/dbname?sslmode=disable
"""


def print_header():
    console.print()
    console.print(
        Panel.fit(
            "[bold cyan]AI Ops Agent[/bold cyan]  [dim]v1.0[/dim]\n"
            "[dim]Autonomous incident responder — Kubernetes + GitOps[/dim]\n"
            f"[dim]Model: {MODEL} · {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}[/dim]",
            border_style="cyan",
            padding=(1, 4),
        )
    )
    console.print()


def print_tool_call(name: str, inputs: dict):
    icons = {
        "get_cluster_status": "🔍",
        "get_pod_logs": "📋",
        "describe_pod": "🔬",
        "read_manifest": "📂",
        "apply_fix": "🔧",
        "force_argocd_sync": "⚡",
        "check_argocd_sync": "🔄",
        "wait_for_healthy": "⏳",
    }
    icon = icons.get(name, "⚙")
    args_str = ", ".join(f"{k}={repr(v)}" for k, v in inputs.items())
    console.print(f"  {icon} [bold yellow]{name}[/bold yellow]([dim]{args_str}[/dim])")


def print_tool_result(name: str, result: str):
    if name == "read_manifest" or name == "apply_fix":
        lang = "yaml" if ".yaml" in str(result) else "text"
        preview = result[:600] + ("..." if len(result) > 600 else "")
        console.print(
            Panel(
                Syntax(preview, lang, theme="monokai", line_numbers=False),
                border_style="dim",
                padding=(0, 1),
            )
        )
    else:
        lines = result.splitlines()
        preview = "\n".join(lines[:20])
        if len(lines) > 20:
            preview += f"\n[dim]... ({len(lines) - 20} more lines)[/dim]"
        console.print(Panel(f"[dim]{preview}[/dim]", border_style="dim", padding=(0, 1)))
    console.print()


def run_agent():
    print_header()

    client = anthropic.Anthropic()
    messages = []

    alert_message = (
        "ALERT: Production incident detected at "
        + datetime.now().strftime("%H:%M:%S")
        + "\n\n"
        "Please investigate the Kubernetes cluster, identify the root cause of the incident, "
        "and resolve it autonomously using GitOps best practices. "
        "Target namespace: default."
    )

    console.print(Panel(
        f"[bold red]⚠  INCIDENT ALERT[/bold red]\n[dim]{alert_message}[/dim]",
        border_style="red",
        padding=(1, 2),
    ))
    console.print()

    messages.append({"role": "user", "content": alert_message})

    iteration = 0
    max_iterations = 12
    incident_start = time.time()

    while iteration < max_iterations:
        iteration += 1

        # Stream the agent response
        text_buffer = ""
        tool_calls = []
        current_tool = None
        current_input_json = ""
        stop_reason = None

        with client.messages.stream(
            model=MODEL,
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        ) as stream:
            for event in stream:
                event_type = event.type

                if event_type == "content_block_start":
                    block = event.content_block
                    if block.type == "text":
                        # Print agent text as it streams
                        if not text_buffer:
                            console.print("[bold cyan]🧠 Agent:[/bold cyan] ", end="")
                        pass
                    elif block.type == "tool_use":
                        if text_buffer:
                            console.print()
                            console.print()
                        current_tool = {"id": block.id, "name": block.name, "input": {}}
                        current_input_json = ""

                elif event_type == "content_block_delta":
                    delta = event.delta
                    if delta.type == "text_delta":
                        console.print(delta.text, end="")
                        text_buffer += delta.text
                    elif delta.type == "input_json_delta":
                        current_input_json += delta.partial_json

                elif event_type == "content_block_stop":
                    if current_tool:
                        import json
                        try:
                            current_tool["input"] = json.loads(current_input_json) if current_input_json else {}
                        except json.JSONDecodeError:
                            current_tool["input"] = {}
                        tool_calls.append(current_tool)
                        current_tool = None
                        current_input_json = ""

                elif event_type == "message_delta":
                    stop_reason = event.delta.stop_reason

        if text_buffer:
            console.print()
            console.print()

        # Build assistant message content
        assistant_content = []
        if text_buffer:
            assistant_content.append({"type": "text", "text": text_buffer})

        tool_results = []

        for tool_call in tool_calls:
            assistant_content.append({
                "type": "tool_use",
                "id": tool_call["id"],
                "name": tool_call["name"],
                "input": tool_call["input"],
            })

            print_tool_call(tool_call["name"], tool_call["input"])

            result = execute_tool(tool_call["name"], tool_call["input"])
            print_tool_result(tool_call["name"], result)

            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tool_call["id"],
                "content": result,
            })

        if assistant_content:
            messages.append({"role": "assistant", "content": assistant_content})

        if tool_results:
            messages.append({"role": "user", "content": tool_results})

        if stop_reason == "end_turn" and not tool_calls:
            break

    elapsed = time.time() - incident_start
    console.print(Rule(style="green"))
    console.print(
        Panel.fit(
            f"[bold green]✓ Incident resolved[/bold green] in [bold]{elapsed:.0f}s[/bold]\n"
            "[dim]Root cause identified → Fix pushed to Git → ArgoCD synced → App healthy[/dim]",
            border_style="green",
            padding=(1, 4),
        )
    )
    console.print()


if __name__ == "__main__":
    missing = [v for v in ["ANTHROPIC_API_KEY"] if not os.environ.get(v)]
    if missing:
        console.print(f"[bold red]Error:[/bold red] Missing environment variables: {', '.join(missing)}")
        sys.exit(1)
    run_agent()
