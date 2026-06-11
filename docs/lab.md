# Lab — Mise en place de l'environnement

## Prérequis

```bash
# macOS
brew install kind kubectl helm git

# Python 3.11+
python3 --version

# Docker Desktop lancé
docker info
```

Comptes nécessaires :
- **GitHub** — pour pousser les fixes via GitOps
- **Anthropic API key** — [console.anthropic.com](https://console.anthropic.com)
- **Docker Hub** — image `aurelops/ia-ops-demo-app` déjà publique

---

## Repos GitHub

| Repo | Rôle |
|------|------|
| `github.com/aurelien-moreau/ia-ops-demo-lab` | Agent IA, scripts, lab (ce repo) |
| `github.com/aurelien-moreau/ia-ops-argo-app` | Manifests K8s — source of truth ArgoCD |
| `github.com/aurelien-moreau/ia-ops-demo-app` | Code Go + Dockerfile + CI/CD → Docker Hub |

---

## Étape 1 — Cloner les repos côte à côte

```bash
git clone git@github.com:aurelien-moreau/ia-ops-demo-lab.git ~/code/ia-ops-demo-lab
git clone git@github.com:aurelien-moreau/ia-ops-argo-app.git ~/code/ia-ops-argo-app
```

Structure attendue :
```
~/code/
├── ia-ops-demo-lab/    ← agent IA, lab scripts
└── ia-ops-argo-app/    ← manifests K8s (lu par ArgoCD + modifié par l'agent)
```

> Les scripts `break.sh`, `reset.sh` et l'agent détectent automatiquement `../ia-ops-argo-app`.

---

## Étape 2 — Configurer l'agent IA

```bash
cd ~/code/ia-ops-demo-lab/agent
cp .env.example .env
```

Éditer `agent/.env` :

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export ARGO_REPO="/Users/TON_USER/code/ia-ops-argo-app"
```

Installer les dépendances Python :

```bash
pip3 install -r requirements.txt
```

---

## Étape 3 — Lancer le lab

```bash
cd ~/code/ia-ops-demo-lab
./lab/setup.sh
```

Le script fait dans l'ordre :

| # | Action | Durée |
|---|--------|-------|
| 1 | Crée le cluster kind `demo-ia-ops` | ~30s |
| 2 | Installe ArgoCD (sync interval : 30s) | ~90s |
| 3 | Installe Stakater Reloader | ~15s |
| 4 | Applique le `root-app` ArgoCD (App of Apps) | ~5s |
| 5 | ArgoCD sync → pull `aurelops/ia-ops-demo-app` depuis Docker Hub | ~60s |
| 6 | Attend que postgres et demo-app soient ready | ~60s |

**Durée totale : ~4 minutes.**

À la fin, le script affiche les credentials ArgoCD.

---

## Accès aux interfaces

| Interface | URL | Auth |
|-----------|-----|------|
| **demo-app** | http://localhost:8081 | — |
| **ArgoCD UI** | https://localhost:8080 | `admin` / affiché par `setup.sh` |
| **K8s Dashboard** *(optionnel)* | http://localhost:8888 | `./lab/install-dashboard.sh` |

---

## Vérifier l'état initial

```bash
kubectl get pods -n default
```
```
NAME                     READY   STATUS    RESTARTS
demo-app-xxx             1/1     Running   0
demo-app-yyy             1/1     Running   0
postgres-zzz             1/1     Running   0
reloader-rrr             1/1     Running   0
```

**Browser** → http://localhost:8081 → page **HEALTHY** (verte)

Chaque refresh change de pod (le nom du pod tourne) — round-robin activé via header `Connection: close`.

---

## Réinitialiser l'environnement

Entre deux runs ou après une démo :

```bash
~/code/ia-ops-demo-lab/scripts/reset.sh
```

Remet dans git :
- `DATABASE_URL` valide dans le ConfigMap
- `replicas: 2` dans le deployment demo-app
- `max_connections=30` dans le deployment postgres

---

## Teardown complet

```bash
~/code/ia-ops-demo-lab/lab/teardown.sh
```

Supprime le cluster kind. Relancer avec `./lab/setup.sh`.

---

## Dashboard K8s (optionnel)

```bash
./lab/install-dashboard.sh

# Dans un terminal séparé :
./lab/port-forward.sh
# Ouvrir http://localhost:8888
# Token dans lab/dashboard-token.txt
```

---

## Checklist avant la démo (J-1)

- [ ] `ia-ops-argo-app` cloné à côté : `ls ~/code/ia-ops-argo-app`
- [ ] `agent/.env` rempli avec une clé Anthropic **valide et non expirée**
- [ ] `./lab/setup.sh` exécuté sans erreur
- [ ] http://localhost:8081 affiche **HEALTHY**
- [ ] ArgoCD https://localhost:8080 → toutes les apps en vert
- [ ] Scénario A testé end-to-end ✓
- [ ] Scénario B testé end-to-end ✓
- [ ] `./scripts/reset.sh` exécuté — environnement propre
- [ ] Terminal 30pt+, fond sombre, notifications désactivées
- [ ] `./scripts/reset.sh` juste avant de monter sur scène
