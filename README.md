# ia-ops-demo-lab

> **Conférence demo** — L'IA qui prend le call de 3h du matin.
>
> Un agent IA détecte une panne en production, investigue les logs, corrige la configuration dans Git et confirme la guérison — sans intervention humaine. Le tout piloté par ArgoCD et GitOps.

---

## Repos GitHub

| Repo | Rôle |
|------|------|
| **ia-ops-demo-lab** *(ce repo)* | Agent IA, scripts, lab kind |
| **ia-ops-argo-app** | Manifests K8s — source of truth GitOps |
| **ia-ops-demo-app** | Code Go + Dockerfile + CI/CD → Docker Hub |

---

## Concept

```
Incident détecté
      │
      ▼
  AI Ops Agent ──► kubectl logs / describe
      │
      ▼
  Root cause identifiée
      │
      ▼
  Commit fix ──► ia-ops-argo-app (GitHub)
      │
      ▼
  ArgoCD sync ──► cluster mis à jour
      │
      ▼
  Application healthy ✓
```

---

## Stack technique

| Couche | Technologie |
|--------|-------------|
| Cluster local | [kind](https://kind.sigs.k8s.io/) |
| GitOps | [ArgoCD](https://argo-cd.readthedocs.io/) — App of Apps |
| Hot-reload ConfigMap | [Stakater Reloader](https://github.com/stakater/Reloader) |
| App de démo | Go — status page auto-refresh + 10 connexions DB/pod |
| Image Docker | `aurelops/ia-ops-demo-app:latest` (Docker Hub) |
| Base de données | PostgreSQL 16 (`max_connections=30`) |
| Agent IA | Python + Claude API (streaming + tool use) |

---

## Documentation

| Doc | Contenu |
|-----|---------|
| [docs/lab.md](docs/lab.md) | Mise en place du lab, setup, accès, checklist J-1 |
| [docs/scenario-mauvaise-config.md](docs/scenario-mauvaise-config.md) | Scénario A — DATABASE_URL malformée |
| [docs/scenario-famine-connexions.md](docs/scenario-famine-connexions.md) | Scénario B — Famine de connexions PostgreSQL |

---

## Démarrage rapide

```bash
# 1. Cloner les deux repos côte à côte
git clone git@github.com:aurelien-moreau/ia-ops-demo-lab.git ~/code/ia-ops-demo-lab
git clone git@github.com:aurelien-moreau/ia-ops-argo-app.git ~/code/ia-ops-argo-app

# 2. Configurer l'agent
cp ~/code/ia-ops-demo-lab/agent/.env.example ~/code/ia-ops-demo-lab/agent/.env
# → remplir ANTHROPIC_API_KEY et ARGO_REPO

# 3. Lancer le lab
cd ~/code/ia-ops-demo-lab && ./lab/setup.sh
```

Voir [docs/lab.md](docs/lab.md) pour le détail complet.

---

## Structure de ce repo

```
ia-ops-demo-lab/
│
├── docs/
│   ├── lab.md                          # Setup complet du lab
│   ├── scenario-mauvaise-config.md     # Scénario A
│   └── scenario-famine-connexions.md   # Scénario B
│
├── agent/
│   ├── main.py          # Agent IA (streaming Claude API + rich terminal)
│   ├── tools.py         # 7 outils kubectl + git
│   ├── requirements.txt
│   └── .env.example
│
├── apps/demo-app/       # Code source Go (miroir de ia-ops-demo-app)
│   ├── main.go
│   ├── Dockerfile
│   └── k8s/             # Non utilisé directement (ArgoCD lit ia-ops-argo-app)
│
├── lab/
│   ├── setup.sh         # Setup complet one-shot
│   ├── kind.yaml        # Cluster config (port mappings 8080/8081)
│   ├── build.sh         # docker build local (dev uniquement)
│   ├── install-dashboard.sh
│   ├── port-forward.sh
│   └── teardown.sh
│
└── scripts/
    ├── reset.sh         # Restaure l'état sain dans ia-ops-argo-app
    └── break.sh         # Injecte DATABASE_URL cassée (scénario A)
```

---

## Outils de l'agent IA

| Outil | Action |
|-------|--------|
| `get_cluster_status` | Vue d'ensemble pods + deployments |
| `get_pod_logs` | Logs d'un pod spécifique |
| `describe_pod` | Events + config du pod |
| `read_manifest` | Lit un fichier YAML depuis `ia-ops-argo-app` |
| `apply_fix` | Écrit le fix, `git commit`, `git push` |
| `check_argocd_sync` | Vérifie le statut de sync ArgoCD |
| `wait_for_healthy` | Attend que les pods soient en `Running` |

Modèle : `claude-sonnet-4-6` — configurable via `AGENT_MODEL` dans `agent/.env`.
