# Schemas — Inventaire des diagrammes Excalidraw

Ouvrir dans [excalidraw.com](https://excalidraw.com) (drag & drop) ou via l'extension VS Code Excalidraw.

## Rappels technologiques

| Fichier | Titre | Section présentation |
|---------|-------|----------------------|
| [01-kubernetes-cluster.excalidraw](01-kubernetes-cluster.excalidraw) | Cluster K8s — Pods, Deployment, ConfigMap, Service | §1 Rappels |
| [02-gitops-model.excalidraw](02-gitops-model.excalidraw) | Modèle GitOps — Developer → Git → ArgoCD → Cluster | §1 Rappels |
| [03-argocd.excalidraw](03-argocd.excalidraw) | ArgoCD — App config, statuts Synced/Healthy, Reloader | §1 Rappels |

## Architecture du lab

| Fichier | Titre | Section présentation |
|---------|-------|----------------------|
| [04-lab-architecture.excalidraw](04-lab-architecture.excalidraw) | Vue globale — Repos GitHub / Cluster KIND / Agent IA | §2 Architecture |
| [05-data-flow.excalidraw](05-data-flow.excalidraw) | Flux de résolution — Incident → outils → fix → guérison | §2 Architecture |

## Agents IA

| Fichier | Titre | Section présentation |
|---------|-------|----------------------|
| [06-agent-vs-llm.excalidraw](06-agent-vs-llm.excalidraw) | LLM simple vs Agent IA — comparaison côte à côte | §3 Agent IA |
| [07-agentic-loop.excalidraw](07-agentic-loop.excalidraw) | La boucle agentique — objectif → LLM → outil → boucle | §3 Agent IA |
| [08-agent-architecture.excalidraw](08-agent-architecture.excalidraw) | Architecture de l'agent — System Prompt + 7 outils | §4 Notre agent |

## Scénarios de démo

| Fichier | Titre | Section présentation |
|---------|-------|----------------------|
| [09-scenario-a.excalidraw](09-scenario-a.excalidraw) | Scénario A — Mauvaise configuration DATABASE_URL | §6 Démo A |
| [10-scenario-b.excalidraw](10-scenario-b.excalidraw) | Scénario B — Famine de connexions PostgreSQL | §7 Démo B |
| [11-connections.excalidraw](11-connections.excalidraw) | Architecture des connexions — avant/après scale | §7 Démo B |

## Pour aller plus loin

| Fichier | Titre | Section présentation |
|---------|-------|----------------------|
| [12-multi-agent.excalidraw](12-multi-agent.excalidraw) | Architecture multi-agents — orchestrateur + 5 agents spécialisés | §8 Suite |
| [13-roadmap.excalidraw](13-roadmap.excalidraw) | Roadmap — Aujourd'hui / Étape 2 / Étape 3 | §8 Suite |

## Palette de couleurs utilisée

| Couleur | Usage |
|---------|-------|
| Bleu `#3b5bdb` / `#dbe4ff` | Pods K8s, infrastructure |
| Violet `#6741d9` / `#e5dbff` | PostgreSQL |
| Mauve `#ae3ec9` / `#f3d9fa` | ArgoCD |
| Jaune `#e67700` / `#fff3bf` | ConfigMap, Git repo |
| Orange `#f08c00` / `#fff9db` | Agent IA |
| Vert `#2f9e44` / `#d3f9d8` | État sain, succès |
| Rouge `#c92a2a` / `#ffe3e3` | Erreur, incident |
| Gris `#495057` / `#f1f3f5` | Neutre, cluster |
