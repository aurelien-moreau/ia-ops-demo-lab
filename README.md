# ia-ops-demo-lab

> **Conférence demo** — L'IA qui prend le call de 3h du matin.
>
> Un agent IA détecte une panne en production, investigue les logs, corrige la configuration dans Git et confirme la guérison — sans intervention humaine. Le tout piloté par ArgoCD et GitOps.

---

## Repos GitHub

| Repo | Contenu | Lien |
|------|---------|------|
| **ia-ops-demo-lab** *(ce repo)* | Agent IA, scripts lab, kind setup | `github.com/aurelien-moreau/ia-ops-demo-lab` |
| **ia-ops-argo-app** | Manifests K8s + ArgoCD (source of truth GitOps) | `github.com/aurelien-moreau/ia-ops-argo-app` |
| **ia-ops-demo-app** | Code Go + Dockerfile + GitHub Actions → DockerHub | `github.com/aurelien-moreau/ia-ops-demo-app` |

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
  ArgoCD sync ──► ConfigMap mis à jour
      │
      ▼
  Stakater Reloader ──► Rolling restart automatique
      │
      ▼
  Application healthy ✓
```

**Scénario de la démo** : la `DATABASE_URL` est malformée (`postgres://`) dans le ConfigMap.
L'app Go affiche une page de status **DÉGRADÉE** (rouge, pulsante) visible dans le browser.
L'agent IA lit les logs, identifie la cause, pousse le fix sur `ia-ops-argo-app`.
ArgoCD synchronise. L'app repasse en **HEALTHY** (vert).

---

## Stack technique

| Couche | Technologie |
|--------|-------------|
| Cluster local | [kind](https://kind.sigs.k8s.io/) |
| GitOps | [ArgoCD](https://argo-cd.readthedocs.io/) (App of Apps) |
| Hot-reload ConfigMap | [Stakater Reloader](https://github.com/stakater/Reloader) |
| Dashboard K8s | [Kubernetes Dashboard v3](https://github.com/kubernetes/dashboard) |
| App de démo | Go (HTTP server + status page auto-refresh 3s) |
| Image Docker | `aurelops/ia-ops-demo-app:latest` (DockerHub) |
| Base de données | PostgreSQL 16 (pod éphémère) |
| Agent IA | Python + [Claude API](https://docs.anthropic.com/) (streaming + tool use) |

---

## Architecture des repos

```
ia-ops-argo-app/          ← ArgoCD surveille CE repo
├── argocd/
│   ├── root-app.yaml     ← App of Apps root (appliquer une fois)
│   └── apps/
│       ├── demo-app.yaml
│       └── postgres.yaml
└── apps/
    ├── demo-app/k8s/
    │   ├── configmap.yaml    ← ← ← LE FICHIER QU'ON CASSE
    │   ├── deployment.yaml   ← image: aurelops/ia-ops-demo-app:latest
    │   └── service.yaml      (NodePort 30081 → localhost:8081)
    └── postgres/k8s/
        ├── deployment.yaml
        └── service.yaml

ia-ops-demo-app/          ← Code source de l'app
├── main.go
├── Dockerfile
└── .github/workflows/
    └── docker-publish.yml  ← build → aurelops/ia-ops-demo-app sur DockerHub

ia-ops-demo-lab/          ← CE repo (orchestration locale)
├── agent/                ← Agent IA Python
├── lab/                  ← Setup kind + ArgoCD + Dashboard
└── scripts/              ← break.sh / reset.sh / demo.sh
```

Quand `configmap.yaml` est modifié dans `ia-ops-argo-app` :
1. ArgoCD détecte le changement (polling 30s)
2. Applique le ConfigMap dans le cluster
3. Reloader voit l'annotation `reloader.stakater.com/auto: "true"` → rolling restart
4. Les pods redémarrent avec la nouvelle config

---

## Prérequis

```bash
# macOS
brew install kind kubectl helm git

# Python 3.11+
python3 --version
```

- **Docker Desktop** doit être en cours d'exécution
- **Anthropic API key** — obtenir sur [console.anthropic.com](https://console.anthropic.com)

---

## Mise en place du lab

### Étape 1 — Cloner les deux repos côte à côte

```bash
git clone git@github.com:aurelien-moreau/ia-ops-demo-lab.git
git clone git@github.com:aurelien-moreau/ia-ops-argo-app.git

# Structure attendue :
# ~/code/
# ├── ia-ops-demo-lab/    ← scripts, agent, lab
# └── ia-ops-argo-app/    ← manifests K8s (lu par ArgoCD ET par break.sh)
```

> `break.sh` et `reset.sh` détectent automatiquement `../ia-ops-argo-app`.
> Pour surcharger : `export ARGO_REPO=/autre/chemin`

### Étape 2 — Configurer l'agent IA

```bash
cp agent/.env.example agent/.env
# Éditer agent/.env :
#   ANTHROPIC_API_KEY=sk-ant-...
#   ARGO_REPO=../ia-ops-argo-app  (optionnel, détecté automatiquement)

cd agent && pip install -r requirements.txt
```

### Étape 3 — Lancer le lab complet

```bash
./lab/setup.sh
```

Le script fait tout dans l'ordre :

| # | Action | Durée |
|---|--------|-------|
| 1 | Crée le cluster kind `demo-ia-ops` | ~30s |
| 2 | Build de l'image + `kind load docker-image` | ~60s |
| 3 | Installe ArgoCD (intervalle sync : 30s) | ~90s |
| 4 | Installe Stakater Reloader | ~15s |
| 5 | Installe Kubernetes Dashboard | ~30s |
| 6 | Applique le `root-app` ArgoCD | ~5s |
| 7 | Attend que postgres et demo-app soient ready | ~60s |

**Durée totale : ~5 minutes.**

---

## Accès aux interfaces

| Interface | URL | Credentials |
|-----------|-----|-------------|
| **demo-app** (status visuel) | http://localhost:8081 | — |
| **ArgoCD UI** | https://localhost:8080 | `admin` / affiché par `setup.sh` |
| **K8s Dashboard** | http://localhost:8888 | token dans `lab/dashboard-token.txt` |

Pour le Dashboard, lancer dans un terminal séparé :

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
- Écrit `DATABASE_URL: "postgres://"` dans `ia-ops-argo-app/apps/demo-app/k8s/configmap.yaml`
- `git commit` + `git push` sur `ia-ops-argo-app`
- Force un refresh ArgoCD

**Ce que voit l'audience :**
- `~10s` : ArgoCD passe en **OutOfSync** puis **Synced**
- `~15s` : Reloader déclenche le rolling restart
- `~20s` : Browser → page **DÉGRADÉE** (rouge, pulsante)
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
→  read_manifest         → configmap.yaml lu depuis ia-ops-argo-app
→  apply_fix             → commit + push du fix sur GitHub
→  check_argocd_sync     → ArgoCD Synced
→  wait_for_healthy      → pods Running ✓

✓ Incident résolu en ~90s
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

Restaure la bonne `DATABASE_URL` dans `ia-ops-argo-app`, force le sync ArgoCD.

---

## Structure de ce repo

```
ia-ops-demo-lab/
│
├── agent/
│   ├── main.py          # Agent IA (streaming Claude API + rich terminal)
│   ├── tools.py         # 7 outils kubectl + git (pointe vers ia-ops-argo-app)
│   ├── requirements.txt
│   └── .env.example     # Ne jamais commiter .env  (protégé par .gitignore)
│
├── lab/
│   ├── setup.sh         # Setup complet one-shot
│   ├── build.sh         # docker build + kind load docker-image
│   ├── kind.yaml        # Cluster config (port mappings 8080/8081)
│   ├── port-forward.sh  # Port-forward K8s Dashboard → localhost:8888
│   └── teardown.sh      # Supprime cluster kind
│
├── scripts/
│   ├── break.sh         # Injecte le bug dans ia-ops-argo-app → push → sync
│   ├── reset.sh         # Restaure l'état sain → push → sync
│   └── demo.sh          # Orchestration complète (break + agent + vérification)
│
└── apps/demo-app/       # Copie locale de l'app Go (source dans ia-ops-demo-app)
    ├── main.go
    ├── Dockerfile
    └── k8s/             # Non utilisé directement — ArgoCD lit ia-ops-argo-app
```

---

## Outils de l'agent IA

| Outil | Action |
|-------|--------|
| `get_cluster_status` | Vue d'ensemble pods + deployments |
| `get_pod_logs` | Logs du container crashé (`--previous`) |
| `describe_pod` | Events + config du pod |
| `read_manifest` | Lit un fichier YAML depuis `ia-ops-argo-app` |
| `apply_fix` | Écrit le fix, `git commit`, `git push` sur `ia-ops-argo-app` |
| `check_argocd_sync` | Vérifie le statut de sync ArgoCD |
| `wait_for_healthy` | Attend que les pods soient en `Running` |

Modèle par défaut : `claude-sonnet-4-6`. Configurable via `AGENT_MODEL` dans `agent/.env`.

---

## CI/CD — Docker Hub

Le repo `ia-ops-demo-app` publie automatiquement l'image sur Docker Hub à chaque push sur `main`.

Image : `aurelops/ia-ops-demo-app:latest`

Secrets GitHub requis dans `ia-ops-demo-app` :

| Secret | Valeur |
|--------|--------|
| `DOCKERHUB_USERNAME` | `aurelops` |
| `DOCKERHUB_TOKEN` | Token Docker Hub (Read/Write) |

Pour rebuilder l'image localement sans CI :

```bash
./lab/build.sh
# docker build + kind load docker-image (pas besoin de Docker Hub)
```

---

## Dépannage

### Le cluster ne démarre pas

```bash
docker info   # vérifier que Docker Desktop est lancé
./lab/teardown.sh && ./lab/setup.sh
```

### ArgoCD ne sync pas

```bash
# Forcer un refresh immédiat
kubectl annotate application demo-app -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Logs du controller
kubectl logs -n argocd deployment/argocd-application-controller --tail=50
```

### Les pods ne redémarrent pas après break.sh

```bash
# Vérifier que Reloader tourne
kubectl get deployment reloader-reloader -n default

# Vérifier l'annotation Reloader sur le Deployment
kubectl get deployment demo-app -n default \
  -o jsonpath='{.metadata.annotations.reloader\.stakater\.com/auto}'
# Doit retourner : true
```

### ImagePullBackOff sur demo-app

```bash
# Rebuilder et recharger dans kind
./lab/build.sh
kubectl rollout restart deployment/demo-app -n default
```

### L'agent ne trouve pas ia-ops-argo-app

```bash
# Vérifier la variable ARGO_REPO dans agent/.env
echo $ARGO_REPO
ls $ARGO_REPO/apps/demo-app/k8s/configmap.yaml

# Ou cloner à côté de ce repo
git clone git@github.com:aurelien-moreau/ia-ops-argo-app.git ../ia-ops-argo-app
```

### Contexte kubectl mauvais

```bash
kubectl config use-context kind-demo-ia-ops
```

### Mot de passe ArgoCD perdu

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## Teardown

```bash
./lab/teardown.sh
# Supprime le cluster kind demo-ia-ops
```

---

## Checklist avant la démo (J-1)

- [ ] `ia-ops-argo-app` cloné à côté : `ls ../ia-ops-argo-app`
- [ ] `agent/.env` rempli avec une clé Anthropic valide
- [ ] `./lab/setup.sh` exécuté sans erreur
- [ ] http://localhost:8081 affiche **HEALTHY** (vert)
- [ ] ArgoCD https://localhost:8080 → toutes les apps en vert
- [ ] `./scripts/break.sh` → browser passe en rouge ✓
- [ ] `./scripts/reset.sh` → browser repasse en vert ✓
- [ ] `cd agent && source .env && python main.py` → agent tourne sans erreur ✓
- [ ] Terminal en grand (30pt+), fond sombre, notifications désactivées
- [ ] `./scripts/reset.sh` juste avant de monter sur scène
