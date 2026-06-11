# IA Ops — Réparation autonome d'infrastructure
### Agents IA + Kubernetes + GitOps

---

## 1. Rappels — Kubernetes, GitOps, ArgoCD

---

### Kubernetes — L'orchestrateur

Kubernetes gère les conteneurs à votre place : déploiement, scaling, redémarrage automatique.

```
┌─────────────────────────────────────────────────────────┐
│                      CLUSTER K8S                        │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Pod 1     │  │   Pod 2     │  │  Postgres   │     │
│  │  demo-app   │  │  demo-app   │  │    Pod      │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│         └──────────────┘                                │
│              Deployment (replica: 2)                    │
│                                                         │
│  ┌──────────────────────────────┐                       │
│  │         ConfigMap            │  ← configuration      │
│  │  DATABASE_URL=postgres://... │                       │
│  └──────────────────────────────┘                       │
└─────────────────────────────────────────────────────────┘

  Kubernetes surveille en permanence :
  pod mort → il le redémarre
  pod manquant → il en crée un nouveau
```

**Concepts clés :**
- **Pod** — un ou plusieurs conteneurs qui tournent ensemble
- **Deployment** — décrit l'état désiré (image, replicas, config)
- **ConfigMap** — configuration injectée dans les pods
- **Service** — point d'entrée réseau stable vers les pods

---

### GitOps — Git est la source de vérité

Avec GitOps, l'état du cluster est décrit dans Git. On ne fait jamais de `kubectl apply` à la main.

```
┌──────────────────────────────────────────────────────────────┐
│                      MODÈLE GITOPS                           │
│                                                              │
│   Developer          Git Repo              Cluster K8s       │
│                                                              │
│   git push  ───►  ┌──────────┐  ◄── pull  ┌──────────────┐  │
│                   │manifests │            │  ArgoCD      │  │
│                   │          │  détecte   │  controller  │  │
│                   │deploy.yaml│  diff  ──► │              │  │
│                   │config.yaml│            └──────┬───────┘  │
│                   └──────────┘                   │ apply     │
│                                                  ▼           │
│                                           ┌──────────────┐   │
│                                           │   Pods       │   │
│                                           │   running    │   │
│                                           └──────────────┘   │
└──────────────────────────────────────────────────────────────┘

  Règle d'or : JAMAIS de modification directe sur le cluster
  Tout passe par un commit Git → ArgoCD fait le reste
```

**Bénéfices :**
- Audit trail complet (qui a changé quoi, quand)
- Rollback = `git revert`
- Environnements reproductibles

---

### ArgoCD — Le moteur GitOps

ArgoCD surveille un repo Git et maintient le cluster en synchronisation avec lui.

```
┌─────────────────────────────────────────────────────────────┐
│                       ARGOCD                                │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  Application "demo-app"                             │   │
│   │                                                     │   │
│   │  Source : github.com/…/ia-ops-argo-app              │   │
│   │  Path   : apps/demo-app/k8s/                        │   │
│   │  Dest   : cluster default / namespace default       │   │
│   │                                                     │   │
│   │  Status : ● Synced   ● Healthy                      │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   Sync interval : 30s   (poll Git toutes les 30 secondes)  │
│   Auto-sync     : ON    (applique dès qu'un diff détecté)  │
│                                                             │
│   App of Apps pattern : un "root-app" qui déploie          │
│   toutes les autres apps ArgoCD                            │
└─────────────────────────────────────────────────────────────┘
```

**Stakater Reloader** (composant bonus dans notre lab) :
Surveille les ConfigMaps. Dès qu'un ConfigMap change → rolling restart automatique des pods qui en dépendent.

---

## 2. Architecture du lab

---

### Vue d'ensemble

```
┌──────────────────────────────────────────────────────────────────────┐
│                            LAB IA OPS                                │
│                                                                      │
│  ┌─────────────────┐         ┌──────────────────────────────────┐   │
│  │   REPOS GITHUB  │         │         CLUSTER KIND             │   │
│  │                 │         │                                  │   │
│  │  ia-ops-demo-lab│         │  ┌────────────┐  ┌───────────┐  │   │
│  │  ├── agent/     │         │  │  demo-app  │  │  demo-app │  │   │
│  │  │   main.py    │         │  │  pod 1     │  │  pod 2    │  │   │
│  │  │   tools.py   │         │  └────────────┘  └───────────┘  │   │
│  │  ├── docs/      │         │         │               │        │   │
│  │  └── scripts/   │         │         └───────────────┘        │   │
│  │                 │  watch  │              Service              │   │
│  │  ia-ops-argo-app│◄───────►│                │                 │   │
│  │  ├── apps/      │  sync   │         ┌──────┴──────┐          │   │
│  │  │   demo-app/  │         │         │  Postgres   │          │   │
│  │  │   postgres/  │         │         │    pod      │          │   │
│  │  └── argocd/    │         │         └─────────────┘          │   │
│  │                 │         │                                  │   │
│  │  ia-ops-demo-app│         │  ┌─────────────────────────────┐ │   │
│  │  ├── main.go    │         │  │         ARGOCD              │ │   │
│  │  └── Dockerfile │         │  │  demo-app : Synced Healthy  │ │   │
│  │        │        │         │  │  postgres  : Synced Healthy  │ │   │
│  │        ▼        │         │  └─────────────────────────────┘ │   │
│  │   Docker Hub    │         │                                  │   │
│  │  (image:latest) │         │  ┌─────────────────────────────┐ │   │
│  └─────────────────┘         │  │  Stakater Reloader          │ │   │
│                              │  │  (restart on ConfigMap change│ │   │
│  ┌─────────────────┐         │  └─────────────────────────────┘ │   │
│  │   AGENT IA      │         └──────────────────────────────────┘   │
│  │                 │                         ▲                       │
│  │  python main.py │─────── kubectl ─────────┘                      │
│  │  + Anthropic API│─────── git push ──────► ia-ops-argo-app        │
│  └─────────────────┘                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Les trois repos

| Repo | Rôle | Modifié par |
|------|------|-------------|
| `ia-ops-demo-lab` | Agent IA, scripts, lab | Développeurs |
| `ia-ops-argo-app` | Manifests K8s — source de vérité | Développeurs + **Agent IA** |
| `ia-ops-demo-app` | Code Go + Dockerfile | Développeurs → Docker Hub |

---

### Flux de données dans le lab

```
                         INCIDENT DÉTECTÉ
                               │
                               ▼
                    ┌──────────────────┐
                    │   AGENT IA       │
                    │   main.py        │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
       kubectl get     kubectl logs    read_manifest
       pods/deploy     (pod logs)      (Git repo)
              │              │              │
              └──────────────┴──────────────┘
                             │
                    DIAGNOSTIC COMPLET
                             │
                             ▼
                    ┌──────────────────┐
                    │   apply_fix()    │
                    │  écrit le fichier│
                    │  git commit      │
                    │  git push        │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │    ARGOCD        │
                    │  détecte le diff │
                    │  applique sur    │
                    │  le cluster      │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Pods redémarrent│
                    │  avec la bonne   │
                    │  configuration   │
                    └──────────────────┘
                             │
                             ▼
                    wait_for_healthy()
                    ✓ Incident résolu
```

---

## 3. Ce qu'est un agent IA

---

### Agent vs. LLM simple

```
┌──────────────────────────────────────────────────────────────┐
│   LLM SIMPLE               │   AGENT IA                      │
│                            │                                  │
│   Question ──► Réponse     │   Objectif donné                 │
│                            │        │                         │
│   Stateless                │        ▼                         │
│   Pas d'actions            │   ┌─────────────────────┐        │
│   Pas de mémoire           │   │     LLM (cerveau)   │        │
│   contextualisée           │   └──────────┬──────────┘        │
│                            │              │ décide             │
│                            │              ▼                   │
│                            │   ┌─────────────────────┐        │
│                            │   │       OUTILS        │        │
│                            │   │  kubectl / git / API│        │
│                            │   └──────────┬──────────┘        │
│                            │              │ résultat           │
│                            │              ▼                   │
│                            │      LLM réfléchit encore        │
│                            │      (boucle jusqu'au but)       │
└──────────────────────────────────────────────────────────────┘
```

---

### La boucle agentique

```
              ┌─────────────────────────────────┐
              │                                 │
              │          OBJECTIF               │
              │  "Résous l'incident en prod"    │
              │                                 │
              └─────────────────┬───────────────┘
                                │
                                ▼
                   ┌────────────────────────┐
              ┌───►│   LLM réfléchit        │
              │    │   (System Prompt +     │
              │    │    Historique des      │
              │    │    échanges)           │
              │    └───────────┬────────────┘
              │                │
              │         Appel d'outil ?
              │                │
              │    ┌───────────┴────────────┐
              │    │                        │
              │    ▼                        ▼
              │  OUI                       NON
              │    │                        │
              │    ▼                        ▼
              │ Exécute l'outil         Réponse finale
              │ (kubectl, git, ...)      (fin de boucle)
              │    │
              │    ▼
              │ Résultat ajouté
              │ à l'historique
              │    │
              └────┘
```

---

### Termes clés

| Terme | Définition simple |
|-------|-------------------|
| **LLM** | Le modèle de langage — le cerveau de l'agent (Claude Sonnet) |
| **Tool / Function Calling** | Capacité du LLM à appeler des fonctions réelles (kubectl, git…) |
| **System Prompt** | Instructions permanentes qui définissent le rôle et les règles de l'agent |
| **Boucle agentique** | Le cycle répété : réfléchir → agir → observer → réfléchir |
| **Streaming** | Les tokens arrivent au fur et à mesure — on voit l'agent "penser" en direct |
| **Max iterations** | Garde-fou : max 12 tours de boucle pour éviter les boucles infinies |
| **Tool result** | Ce que renvoie l'outil — devient le contexte de la prochaine réflexion |

---

### Comment on code un outil

```python
# 1. Décrire l'outil au LLM (schéma JSON)
{
    "name": "get_pod_logs",
    "description": "Get recent logs from a specific pod.",
    "input_schema": {
        "type": "object",
        "properties": {
            "pod_name": {"type": "string"},
            "lines":    {"type": "integer", "default": 50}
        },
        "required": ["pod_name"]
    }
}

# 2. Implémenter l'outil en Python
def get_pod_logs(pod_name: str, lines: int = 50) -> str:
    return subprocess.run(
        ["kubectl", "logs", pod_name, f"--tail={lines}"],
        capture_output=True, text=True
    ).stdout

# Le LLM décide QUAND appeler cet outil — pas le développeur.
```

---

## 4. Notre agent de réparation d'infrastructure

---

### Architecture de l'agent

```
┌──────────────────────────────────────────────────────────────┐
│                    AGENT IA OPS                              │
│                                                              │
│  System Prompt (rôle + règles)                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  "Tu es un SRE expert. Toujours passer par GitOps.    │  │
│  │   N'applique jamais kubectl directement.              │  │
│  │   Vérifie la guérison après chaque fix."              │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  7 outils disponibles                                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  🔍 get_cluster_status   → kubectl get pods/deploys  │   │
│  │  📋 get_pod_logs          → kubectl logs <pod>       │   │
│  │  🔬 describe_pod          → kubectl describe pod     │   │
│  │  📂 read_manifest         → lire fichier YAML (Git)  │   │
│  │  🔧 apply_fix             → écrire + git push        │   │
│  │  🔄 check_argocd_sync     → état de sync ArgoCD      │   │
│  │  ⏳ wait_for_healthy      → attendre pods Running    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Modèle : claude-sonnet-4-6                                  │
│  Max iterations : 12                                         │
│  Déclencheur : alerte manuelle (python main.py)              │
└──────────────────────────────────────────────────────────────┘
```

---

### Principes de l'agent

1. **GitOps first** — aucun `kubectl apply` direct. Tout fix = commit + push
2. **Observer avant d'agir** — lire les logs, lire les manifests, comprendre la cause avant d'écrire
3. **Transparent** — chaque action est expliquée en langage naturel en temps réel
4. **Confirmer la guérison** — `wait_for_healthy` systématique après chaque fix

---

## 5. Démo

---

### État initial du lab

```
kubectl get pods -n default
```
```
NAME                     READY   STATUS    AGE
demo-app-xxx             1/1     Running   5m
demo-app-yyy             1/1     Running   5m
postgres-zzz             1/1     Running   5m
reloader-rrr             1/1     Running   5m
```

**http://localhost:8081** → page HEALTHY (verte)
**https://localhost:8080** → ArgoCD — toutes les apps en vert

---

## 6. Scénario A — Mauvaise configuration

---

### Concept

```
  DÉVELOPPEUR pousse une mauvaise config dans Git
                       │
                       ▼
            ArgoCD détecte le diff
                       │
                       ▼
              ConfigMap mis à jour
                       │
                       ▼
        Reloader → rolling restart des pods
                       │
                       ▼
     App démarre avec DATABASE_URL invalide
                       │
                       ▼
    [ERROR] DATABASE_URL is invalid: 'postgres://'
                       │
                       ▼
      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      ░░░░   AGENT IA DÉCLENCHÉ          ░░░░
      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                       │
         ┌─────────────┼────────────┐
         ▼             ▼            ▼
    get_cluster   get_pod_logs  read_manifest
     _status       (logs rouges)   (configmap)
         │             │            │
         └─────────────┴────────────┘
                       │
            DATABASE_URL: "postgres://"
            → URL incomplète identifiée
                       │
                       ▼
               apply_fix() → git push
                       │
                       ▼
     ArgoCD sync → Reloader restart
                       │
                       ▼
          App HEALTHY ✓   (~90 secondes)
```

---

### Ce qui change dans Git

```yaml
# AVANT (cassé)                    # APRÈS (fix de l'agent)
---                                ---
DATABASE_URL: "postgres://"        DATABASE_URL: "postgres://app:s3cr3t@
                                     postgres.default.svc.cluster.local:
                                     5432/appdb?sslmode=disable"
```

```
git log --oneline ia-ops-argo-app
─────────────────────────────────────────────
a1b2c3d  fix: restore valid DATABASE_URL           ← posé par l'agent
f4e5d6c  fix: update database endpoint config      ← le bug
```

---

### Durée totale : ~90 secondes — zéro intervention humaine

---

## 7. Scénario B — Famine de connexions PostgreSQL

---

### Concept

```
  ÉQUIPE scale demo-app de 2 → 5 replicas
                       │
                       ▼
         ArgoCD déploie 3 nouveaux pods
                       │
                       ▼
    5 pods × 10 connexions = 50 connexions demandées
                       │
                       ▼
       PostgreSQL : max_connections = 30
                       │
                  50 > 30 → REJET
                       │
           ┌───────────┴───────────┐
           ▼                       ▼
    Pod 1-3 : HEALTHY         Pod 4-5 : DÉGRADÉ
    (connectés en premier)    (plus de place)
           │                       │
           └───────────┬───────────┘
                       │
    Browser : certains refreshes VERT, d'autres ROUGE
                       │
                       ▼
      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      ░░░░   AGENT IA DÉCLENCHÉ          ░░░░
      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
  get_cluster      get_pod_logs    get_pod_logs
   _status          (app pods)      (postgres)
       │               │               │
       │   "too many clients"   "FATAL: too many
       │   "max_connections      clients already"
       │    limit reached"
       └───────────────┴───────────────┘
                       │
          read_manifest(postgres/deployment.yaml)
          → args: ["-c", "max_connections=30"]
                       │
                       ▼
          apply_fix → max_connections=30 → 200
          git commit + push
                       │
                       ▼
      ArgoCD sync → postgres restart (nouvelle config)
                       │
                       ▼
          wait_for_healthy(app=demo-app)
          ✓ 5 pods Running   (~120 secondes)
```

---

### Architecture des connexions

```
  AVANT LE SCALE (état sain)
  ┌──────────┐  ┌──────────┐
  │  Pod 1   │  │  Pod 2   │      Postgres
  │ 10 conn  │  │ 10 conn  │  →  max_connections=30
  └──────────┘  └──────────┘     20 utilisées ✓

  APRÈS LE SCALE (état cassé)
  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
  │ Pod 1  │ │ Pod 2  │ │ Pod 3  │ │ Pod 4  │ │ Pod 5  │
  │ 10conn │ │ 10conn │ │ 10conn │ │  ✗ REJ │ │  ✗ REJ │
  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘
     OK         OK         OK      max_connections=30 dépassé

  APRÈS LE FIX DE L'AGENT
  max_connections=200 → tous les pods se connectent ✓
```

---

### Durée totale : ~120 secondes — zéro intervention humaine

---

## 8. Pour aller plus loin

---

### Limites de l'agent actuel

```
  ┌─────────────────────────────────────────────────────┐
  │  Agent actuel — mono-agent généraliste              │
  │                                                     │
  │  + Simple à comprendre et à déployer               │
  │  + Efficace sur 2 types d'incidents connus         │
  │                                                     │
  │  − Déclenché manuellement (python main.py)         │
  │  − Connaît uniquement les 2 scénarios du lab       │
  │  − Pas de mémoire entre les incidents              │
  │  − Pas d'alerte proactive                         │
  └─────────────────────────────────────────────────────┘
```

---

### Architecture multi-agents (prochaine étape)

```
┌──────────────────────────────────────────────────────────────────┐
│                   ORCHESTRATEUR                                  │
│                                                                  │
│   Reçoit l'alerte → triage → délègue à l'agent spécialisé       │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │              AGENTS SPÉCIALISÉS                         │   │
│   │                                                          │   │
│   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │   │
│   │  │  Agent DB    │  │  Agent Réseau│  │  Agent Coût  │  │   │
│   │  │              │  │              │  │              │  │   │
│   │  │ connections  │  │ DNS, TLS,    │  │ scaling,     │  │   │
│   │  │ slow queries │  │ timeouts     │  │ rightsizing  │  │   │
│   │  │ migrations   │  │ ingress      │  │ spot eviction│  │   │
│   │  └──────────────┘  └──────────────┘  └──────────────┘  │   │
│   │                                                          │   │
│   │  ┌──────────────┐  ┌──────────────┐                     │   │
│   │  │  Agent Sécu  │  │  Agent Perfo │                     │   │
│   │  │              │  │              │                     │   │
│   │  │ secrets, RBAC│  │ CPU, mémoire │                     │   │
│   │  │ CVE, policies│  │ HPA, throttle│                     │   │
│   │  └──────────────┘  └──────────────┘                     │   │
│   └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

### Intégrations possibles

```
  SOURCES D'ALERTES                SORTIES POSSIBLES

  Prometheus / AlertManager   →    Fix Git (déjà en place)
  PagerDuty / OpsGenie        →    Commentaire GitHub PR
  Logs Datadog / Loki         →    Message Slack avec rapport
  Webhook K8s                 →    Ticket Jira auto
  Cron (sanity check)         →    Rollback automatique
                                   Escalade humaine si besoin
```

---

### Roadmap vers un vrai système autonome

```
  AUJOURD'HUI             ÉTAPE 2              ÉTAPE 3
  ─────────────           ─────────────        ─────────────
  Déclenchement           Déclenchement        Détection
  manuel                  sur webhook          proactive
                          (AlertManager)       (scraping)

  1 agent                 Orchestrateur        Multi-agents
  généraliste             + 2 agents           spécialisés
                          spécialisés          + mémoire

  2 scénarios             5-10 scénarios       Apprentissage
  hard-codés              documentés           des nouveaux
                                               patterns
```

---

### Ce qu'on a montré aujourd'hui

```
  ✓  Un agent qui lit les signaux (logs, état du cluster)
  ✓  Comprend la cause racine sans règles pré-programmées
  ✓  Applique le fix de la bonne façon (GitOps, pas de hack)
  ✓  Laisse une piste d'audit dans Git
  ✓  Confirme la guérison avant de clore l'incident
  ✓  ~100 lignes de Python + 7 outils = agent de production
```

---

> **"Le modèle de langage est le cerveau.  
> Les outils sont les mains.  
> GitOps est la discipline qui rend ça sûr."**

---

## Ressources

| Quoi | Lien |
|------|------|
| Code du lab | `github.com/aurelien-moreau/ia-ops-demo-lab` |
| Manifests K8s | `github.com/aurelien-moreau/ia-ops-argo-app` |
| Anthropic Tool Use | `docs.anthropic.com/tools` |
| ArgoCD docs | `argo-cd.readthedocs.io` |
| Stakater Reloader | `github.com/stakater/Reloader` |
