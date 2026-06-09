# demo-ia-ops

> **Conférence demo** — L'IA qui prend le call de 3h du matin.
>
> Un agent IA détecte une panne en production, investigue les logs, corrige la configuration dans Git et confirme la guérison — sans intervention humaine. Le tout piloté par ArgoCD et GitOps.

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
  Commit fix ──► GitHub
      │
      ▼
  ArgoCD sync ──► ConfigMap mis à jour
      │
      ▼
  Reloader ──► Rolling restart
      │
      ▼
  Application healthy ✓
```

**Scénario de la démo** : la `DATABASE_URL` est malformée (`postgres://`) après un mauvais déploiement.
L'app Go affiche une page de status **DÉGRADÉE** (rouge) visible dans le browser.
L'agent IA lit les logs, identifie la cause, pousse le fix sur GitHub.
ArgoCD synchronise. L'app repasse en **HEALTHY** (vert).

---

## Stack technique

| Couche | Technologie |
|--------|-------------|
| Cluster local | [kind](https://kind.sigs.k8s.io/) |
| GitOps | [ArgoCD](https://argo-cd.readthedocs.io/) (App of Apps) |
| Hot-reload ConfigMap | [Stakater Reloader](https://github.com/stakater/Reloader) |
| Dashboard K8s | [Kubernetes Dashboard v3](https://github.com/kubernetes/dashboard) |
| App de démo | Go (HTTP server + status page auto-refresh) |
| Base de données | PostgreSQL 16 (pod éphémère) |
| Agent IA | Python + [Claude API](https://docs.anthropic.com/) (streaming + tool use) |
| Registry locale | Docker registry:2 |

---

## Architecture GitOps (App of Apps)

```
argocd/
├── root-app.yaml          ← Appliqué une fois manuellement
└── apps/
    ├── postgres.yaml      ← Géré par root-app
    └── demo-app.yaml      ← Géré par root-app

apps/
├── postgres/k8s/          ← Manifests PostgreSQL
└── demo-app/k8s/
    ├── configmap.yaml     ← ← ← LE FICHIER QU'ON CASSE
    ├── deployment.yaml
    └── service.yaml       (NodePort 30081 → localhost:8081)
```

Quand `configmap.yaml` est modifié sur GitHub :
1. ArgoCD détecte le changement (polling 30s)
2. Applique le ConfigMap dans le cluster
3. Reloader voit l'annotation `reloader.stakater.com/auto: "true"` → rolling restart
4. Les pods redémarrent avec la nouvelle config

---

## Prérequis

**Outils à installer :**

```bash
# macOS
brew install kind kubectl helm git

# Python 3.11+
python3 --version
```

**Comptes nécessaires :**

- GitHub (repo public ou privé accessible depuis le cluster)
- [Anthropic API key](https://console.anthropic.com/) pour l'agent IA

**Docker Desktop** doit être en cours d'exécution.

---

## Mise en place du lab (3 étapes)

### Étape 1 — Créer le repo GitHub

```bash
git init
git add .
git commit -m "feat: initial demo setup"

# Avec GitHub CLI
gh repo create demo-ia-ops --public --source=. --push

# Ou manuellement : créer le repo sur github.com puis :
git remote add origin https://github.com/TON_USER/demo-ia-ops.git
git push -u origin main
```

### Étape 2 — Configurer l'URL du repo dans les manifests ArgoCD

```bash
./lab/configure.sh https://github.com/TON_USER/demo-ia-ops.git
```

Ce script remplace le placeholder `YOUR_ORG` dans tous les fichiers ArgoCD. Committer et pousser le résultat :

```bash
git add argocd/ .lab-env
git commit -m "chore: configure argocd repo url"
git push
```

### Étape 3 — Lancer le lab complet

```bash
./lab/setup.sh
```

Le script fait tout dans l'ordre :

| # | Action | Durée |
|---|--------|-------|
| 1 | Crée la registry Docker locale (`localhost:5001`) | ~5s |
| 2 | Crée le cluster kind `demo-ia-ops` | ~30s |
| 3 | Build + push de l'image `aurelops/ia-ops-demo-app` | ~60s |
| 4 | Installe ArgoCD (intervalle sync : 30s) | ~90s |
| 5 | Installe Stakater Reloader | ~15s |
| 6 | Installe Kubernetes Dashboard | ~30s |
| 7 | Applique le `root-app` ArgoCD | ~5s |
| 8 | Attend que postgres et demo-app soient ready | ~60s |

**Durée totale : ~5 minutes.**

À la fin, le script affiche les URLs et les credentials.

---

## Configurer l'agent IA

```bash
cp agent/.env.example agent/.env
```

Éditer `agent/.env` :

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export REPO_PATH="/chemin/vers/demo-ia-ops"   # optionnel, détecté automatiquement
```

Installer les dépendances Python :

```bash
cd agent
pip install -r requirements.txt
```

---

## Accès aux interfaces

| Interface | URL | Credentials |
|-----------|-----|-------------|
| **demo-app** (status visuel) | http://localhost:8081 | — |
| **ArgoCD UI** | https://localhost:8080 | `admin` / voir output de `setup.sh` |
| **Kubernetes Dashboard** | http://localhost:8888 | token dans `lab/dashboard-token.txt` |

Pour le Dashboard, lancer le port-forward dans un terminal séparé :

```bash
./lab/port-forward.sh
```

---

## Déroulé de la démo (sur scène)

### Acte 1 — État sain (1 min)

Ouvrir http://localhost:8081 — montrer la page **HEALTHY** (verte).

Montrer ArgoCD sur https://localhost:8080 — toutes les apps en vert.

```bash
kubectl get pods -n default
# demo-app-xxx   2/2   Running   0   ...
# postgres-xxx   1/1   Running   0   ...
```

---

### Acte 2 — Injection du bug (30 sec)

```bash
./scripts/break.sh
```

Ce que fait le script :
- Écrit `DATABASE_URL: "postgres://"` dans `configmap.yaml`
- Commit + push sur GitHub
- Force un refresh ArgoCD

**Ce que voit l'audience :**
- `~15s` : ArgoCD passe en **OutOfSync** puis **Synced**
- `~20s` : Reloader déclenche le rolling restart
- `~25s` : Browser → page **DÉGRADÉE** (rouge, pulsante)
- `~40s` : `kubectl get pods` → `CrashLoopBackOff`
- ArgoCD UI → app en état **Degraded**

---

### Acte 3 — L'agent IA intervient (2-3 min)

```bash
cd agent && source .env && python main.py
```

L'agent streame son raisonnement en live dans le terminal :

```
→  get_cluster_status    → pods en CrashLoopBackOff détectés
→  get_pod_logs          → FATAL: DATABASE_URL is invalid: 'postgres://'
→  describe_pod          → events confirmés
→  read_manifest         → configmap.yaml lu depuis Git
→  apply_fix             → commit + push du fix sur GitHub
→  check_argocd_sync     → ArgoCD Synced
→  wait_for_healthy      → pods Running ✓

✓ Incident résolu en 87s
```

---

### Acte 4 — Guérison (30 sec)

- ArgoCD UI → retour en **Healthy**
- Browser → page **HEALTHY** (verte)
- `kubectl get pods` → tous en `Running`

**Message clé** : *Le fix est dans Git. La piste d'audit est complète. Aucun humain n'a été réveillé.*

---

## Réinitialiser la démo (entre deux runs)

```bash
./scripts/reset.sh
```

Restaure la bonne `DATABASE_URL` dans Git, force le sync ArgoCD.

---

## Structure du projet

```
demo-ia-ops/
│
├── apps/
│   ├── demo-app/
│   │   ├── main.go              # Serveur HTTP Go (status page + /health)
│   │   ├── Dockerfile           # Build multi-stage
│   │   └── k8s/
│   │       ├── configmap.yaml   # ← contient DATABASE_URL (le fichier cassé)
│   │       ├── deployment.yaml  # annotation Reloader, liveness probe
│   │       └── service.yaml     # NodePort 30081
│   │
│   └── postgres/
│       └── k8s/
│           ├── deployment.yaml  # postgres:16-alpine
│           └── service.yaml     # ClusterIP sur port 5432
│
├── argocd/
│   ├── root-app.yaml            # App of Apps root (appliquer une fois)
│   └── apps/
│       ├── demo-app.yaml        # Application ArgoCD → apps/demo-app/k8s
│       └── postgres.yaml        # Application ArgoCD → apps/postgres/k8s
│
├── agent/
│   ├── main.py                  # Agent IA (streaming, rich output)
│   ├── tools.py                 # 7 outils : kubectl + git
│   ├── requirements.txt
│   └── .env.example
│
├── lab/
│   ├── configure.sh             # Injecte l'URL GitHub dans les manifests
│   ├── setup.sh                 # Setup complet du lab (one-shot)
│   ├── build.sh                 # Build + push image vers registry locale
│   ├── kind.yaml                # Config du cluster kind (port mappings)
│   ├── port-forward.sh          # Port-forward pour le Dashboard
│   └── teardown.sh              # Supprime cluster + registry
│
└── scripts/
    ├── break.sh                 # Injecte le bug → commit → push → sync
    ├── reset.sh                 # Restaure l'état sain → commit → push → sync
    └── demo.sh                  # Orchestration complète du demo
```

---

## Outils de l'agent IA

L'agent dispose de 7 outils `kubectl` + `git` :

| Outil | Action |
|-------|--------|
| `get_cluster_status` | Vue d'ensemble pods + deployments |
| `get_pod_logs` | Logs du container crashé (`--previous`) |
| `describe_pod` | Events + config du pod |
| `read_manifest` | Lit un fichier YAML depuis le repo Git |
| `apply_fix` | Écrit le fix, `git commit`, `git push` |
| `check_argocd_sync` | Vérifie le statut de sync ArgoCD |
| `wait_for_healthy` | Attend que les pods soient en `Running` |

Modèle par défaut : `claude-sonnet-4-6`. Configurable via `AGENT_MODEL` dans `.env`.

---

## Dépannage

### Le cluster ne démarre pas

```bash
# Vérifier que Docker Desktop est lancé
docker info

# Recréer proprement
./lab/teardown.sh
./lab/setup.sh
```

### ArgoCD ne sync pas

```bash
# Forcer un refresh manuel
kubectl annotate application demo-app -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Vérifier les logs ArgoCD
kubectl logs -n argocd deployment/argocd-application-controller --tail=50
```

### Les pods ne redémarrent pas après le break

```bash
# Vérifier que Reloader tourne
kubectl get deployment reloader-reloader -n default

# Vérifier l'annotation sur le Deployment
kubectl get deployment demo-app -n default -o jsonpath='{.metadata.annotations}'
```

### L'image demo-app ne se charge pas (`ImagePullBackOff`)

```bash
# Rebuild et repush
./lab/build.sh

# Forcer le redéploiement
kubectl rollout restart deployment/demo-app -n default
```

### L'agent ne trouve pas kubectl

```bash
# Vérifier le contexte kubectl
kubectl config current-context
# Doit retourner : kind-demo-ia-ops

# Si ce n'est pas le cas
kubectl config use-context kind-demo-ia-ops
```

### Mot de passe ArgoCD perdu

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## Teardown

Pour tout supprimer après la démo :

```bash
./lab/teardown.sh
```

Supprime le cluster kind et la registry Docker locale.

---

## Checklist avant la démo (J-1)

- [ ] `./lab/setup.sh` s'est exécuté sans erreur
- [ ] http://localhost:8081 affiche **HEALTHY** (vert)
- [ ] ArgoCD https://localhost:8080 → toutes les apps en vert
- [ ] `./scripts/break.sh` → browser passe en rouge ✓
- [ ] `./scripts/reset.sh` → browser repasse en vert ✓
- [ ] `cd agent && python main.py` → agent tourne sans erreur ✓
- [ ] Terminal en grand (30pt+), fond sombre, notifications désactivées
- [ ] `./scripts/reset.sh` pour remettre l'état sain avant de monter sur scène
