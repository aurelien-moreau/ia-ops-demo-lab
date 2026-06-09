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
| 2 | Installe ArgoCD (intervalle sync : 30s) | ~90s |
| 3 | Installe Stakater Reloader | ~15s |
| 4 | Applique le `root-app` ArgoCD | ~5s |
| 5 | ArgoCD sync → pull `aurelops/ia-ops-demo-app` depuis Docker Hub | ~60s |
| 6 | Attend que postgres et demo-app soient ready | ~60s |

**Durée totale : ~4 minutes.** Aucun build local nécessaire — l'image est tirée directement depuis Docker Hub.

> **Kubernetes Dashboard** non inclus par défaut (chart Helm instable). Pour l'installer séparément :
> ```bash
> ./lab/install-dashboard.sh
> ```

---

## Accès aux interfaces

| Interface | URL | Credentials |
|-----------|-----|-------------|
| **demo-app** (status visuel) | http://localhost:8081 | — |
| **ArgoCD UI** | https://localhost:8080 | `admin` / affiché par `setup.sh` |
| **K8s Dashboard** *(optionnel)* | http://localhost:8888 | token dans `lab/dashboard-token.txt` |

Pour le Dashboard (si installé via `./lab/install-dashboard.sh`), lancer dans un terminal séparé :

```bash
./lab/port-forward.sh
```

---

## Déroulé de la démo (sur scène — pas à pas)

> Tout se fait à la main pour expliquer chaque étape au fur et à mesure.
> Prépare **3 fenêtres** : terminal, browser sur http://localhost:8081, ArgoCD sur https://localhost:8080.

---

### Acte 1 — Montrer l'état sain

**Terminal :**
```bash
kubectl get pods -n default
```
```
NAME                     READY   STATUS    RESTARTS
demo-app-xxx             1/1     Running   0
demo-app-yyy             1/1     Running   0
postgres-zzz             1/1     Running   0
```

**Browser** → http://localhost:8081 → page **HEALTHY** (verte)

**ArgoCD** → https://localhost:8080 → toutes les apps en vert

> *"Voilà notre stack en production : deux replicas de l'app, une base PostgreSQL, tout géré par ArgoCD depuis GitHub."*

---

### Acte 2 — Introduire le bug manuellement

Ouvrir `~/code/ia-ops-argo-app/apps/demo-app/k8s/configmap.yaml` et modifier la `DATABASE_URL` :

```yaml
# Avant (sain)
DATABASE_URL: "postgres://app:s3cr3t@postgres.default.svc.cluster.local:5432/appdb?sslmode=disable"

# Après (cassé)
DATABASE_URL: "postgres://"
```

Commiter et pousser :

```bash
cd ~/code/ia-ops-argo-app
git add apps/demo-app/k8s/configmap.yaml
git commit -m "fix: update database endpoint"
git push
```

> *"Un développeur vient de pousser une mauvaise configuration en production. Ça arrive."*

**Ce que voit l'audience dans les secondes qui suivent :**

| Délai | Événement |
|-------|-----------|
| ~10s | ArgoCD passe **OutOfSync** → **Synced** |
| ~15s | Reloader détecte le changement → rolling restart |
| ~20s | Browser → page **DÉGRADÉE** (rouge, pulsante) |
| ~20s | ArgoCD UI → app en état **Degraded** |

```bash
# Montrer les logs du pod
kubectl logs -l app=demo-app -n default --tail=5
# FATAL: DATABASE_URL is invalid: 'postgres://'
```

---

### Acte 3 — Lancer l'agent IA

```bash
cd ~/code/ia-ops-demo-lab/agent
source .env
python3 main.py
```

L'agent streame son raisonnement en live dans le terminal :

```
🤖 AI Ops Agent

⚠  INCIDENT TRIGGERED

🧠 Agent: Je vais commencer par inspecter l'état du cluster...

🔧 get_cluster_status(namespace=default)
   → demo-app pods: Running mais Unready

🔧 get_pod_logs(pod_name=demo-app-xxx, previous=true)
   → FATAL: DATABASE_URL is invalid: 'postgres://'

🔧 read_manifest(path=apps/demo-app/k8s/configmap.yaml)
   → DATABASE_URL: "postgres://"  ← trouvé

🧠 Agent: Root cause identifiée — DATABASE_URL malformée.
          Correction en cours...

🔧 apply_fix(path=apps/demo-app/k8s/configmap.yaml, ...)
   → ✓ commit + push sur ia-ops-argo-app

🔧 check_argocd_sync(app_name=demo-app)
   → Synced ✓

🔧 wait_for_healthy(label_selector=app=demo-app)
   → ✓ All pods Running

✓ Incident résolu en ~90s
```

> *"L'agent a lu les logs, trouvé la cause, corrigé le fichier dans Git et attendu la confirmation. Aucun humain n'a été réveillé."*

---

### Acte 4 — Montrer la guérison

**ArgoCD** → retour en **Healthy** (vert)

**Browser** → page **HEALTHY** (verte)

```bash
kubectl get pods -n default
# demo-app-xxx   1/1   Running   0
```

```bash
# Montrer le commit du fix dans Git
git -C ~/code/ia-ops-argo-app log --oneline -3
```

> *"Le fix est dans Git. La piste d'audit est complète. Le cluster s'est auto-guéri."*

---

## Réinitialiser entre deux runs

Si tu veux relancer la démo depuis un état sain :

```bash
cd ~/code/ia-ops-argo-app
# Remettre la bonne DATABASE_URL dans configmap.yaml
git add apps/demo-app/k8s/configmap.yaml
git commit -m "fix: restore database configuration"
git push
```

Ou utiliser le script :
```bash
~/code/ia-ops-demo-lab/scripts/reset.sh
```

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

Pour rebuilder l'image localement (dev uniquement, pas nécessaire pour le lab) :

```bash
./lab/build.sh
# docker build + kind load docker-image
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
