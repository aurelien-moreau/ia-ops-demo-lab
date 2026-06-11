# Scénario B — Famine de connexions PostgreSQL

> *L'équipe scale l'application à 5 replicas. Chaque pod consomme 10 connexions PostgreSQL. Le serveur est configuré à `max_connections=30`. PostgreSQL commence à rejeter les connexions. L'agent IA détecte la saturation dans les logs, augmente `max_connections` dans Git, ArgoCD redémarre PostgreSQL avec la nouvelle config.*

---

## Concept

```
Scale demo-app → 5 replicas (via Git + ArgoCD)
         │
         ▼
5 pods × 10 connexions = 50 connexions demandées
         │
         ▼
PostgreSQL max_connections=30 → REJET
         │
         ▼
[ERROR] PostgreSQL rejected: too many clients
         │
         ▼
Agent IA → logs app + logs postgres → lit deployment postgres
         │
         ▼
Modifie max_connections=30 → 200 dans deployment.yaml → push
         │
         ▼
ArgoCD sync → postgres restart → nouvelles connexions acceptées
         │
         ▼
Tous les pods HEALTHY ✓
```

---

## Architecture des connexions

```
demo-app (chaque pod)
  └── 10 connexions persistantes → postgres

Limite postgres : max_connections=30

État sain  : 2 pods × 10 =  20 connexions  ✓ (< 30)
État cassé : 5 pods × 10 =  50 connexions  ✗ (> 30 → rejet)
```

**Fichier à corriger :**

```
ia-ops-argo-app/
└── apps/postgres/k8s/
    └── deployment.yaml    ← arg "-c max_connections=30"
```

---

## Acte 1 — Montrer l'état sain

```bash
kubectl get pods -n default
```
```
demo-app-aaa   1/1   Running   0
demo-app-bbb   1/1   Running   0
postgres-zzz   1/1   Running   0
```

**Browser** → http://localhost:8081 → **HEALTHY**

Carte `DB Connections (this pod)` : **10 / 10 held open**

Montrer les logs au démarrage :
```bash
kubectl logs -l app=demo-app -n default --prefix=true --tail=5
```
```
[demo-app-aaa] [INFO]  DB connection 1/10 established
[demo-app-aaa] [INFO]  DB connection 10/10 established
[demo-app-aaa] [INFO]  DB pool ready: all 10 connections established
```

> *"Chaque pod maintient 10 connexions persistantes vers PostgreSQL. Avec 2 pods, on est à 20/30 connexions disponibles."*

---

## Acte 2 — Scaler à 5 replicas (le bug)

Ouvrir `~/code/ia-ops-argo-app/apps/demo-app/k8s/deployment.yaml` :

```yaml
# Avant
replicas: 2

# Après
replicas: 5
```

Commiter et pousser :

```bash
cd ~/code/ia-ops-argo-app
git add apps/demo-app/k8s/deployment.yaml
git commit -m "scale: increase demo-app to 5 replicas for higher load"
git push
```

> *"L'équipe scale l'app pour absorber plus de charge. Personne n'a pensé aux connexions PostgreSQL."*

**Timings après le push :**

| Délai | Événement |
|-------|-----------|
| ~10s | ArgoCD sync → 3 nouveaux pods démarrent |
| ~15s | Pods 1-3 déjà connectés occupent 30 connexions |
| ~20s | Pod 4 tente sa 1ère connexion → **REJET** postgres |
| ~25s | Pod 5 tente sa 1ère connexion → **REJET** postgres |
| ~30s | Browser (round-robin) alterne pods VERT / ROUGE |

**Montrer les logs de tous les pods :**

```bash
kubectl logs -l app=demo-app -n default --prefix=true --tail=5
```
```
[demo-app-aaa] [INFO]  DB pool ready: all 10 connections established
[demo-app-bbb] [INFO]  DB pool ready: all 10 connections established
[demo-app-ccc] [INFO]  DB pool ready: all 10 connections established
[demo-app-ddd] [ERROR] PostgreSQL rejected connection 1/10: too many clients
[demo-app-ddd] [ERROR] Database max_connections limit reached — reduce pod count or increase postgres max_connections
[demo-app-eee] [ERROR] PostgreSQL rejected connection 1/10: too many clients
```

**Montrer les logs PostgreSQL :**

```bash
kubectl logs -l app=postgres -n default --tail=10
```
```
FATAL:  sorry, too many clients already
FATAL:  sorry, too many clients already
LOG:   connection received: host=10.244.0.x
FATAL:  sorry, too many clients already
```

**Browser** → refresh plusieurs fois → certains pods **ROUGE**, certains **VERT**

---

## Acte 3 — Lancer l'agent IA

```bash
cd ~/code/ia-ops-demo-lab/agent
source .env
python3 main.py
```

**Ce que l'audience voit streamer en live :**

```
╭─────────────────────────────────────────────────────╮
│  AI Ops Agent  v1.0                                  │
│  Autonomous incident responder — Kubernetes + GitOps │
╰─────────────────────────────────────────────────────╯

⚠  INCIDENT ALERT

🧠 Agent: Inspection du cluster...

🔍 get_cluster_status(namespace=default)
   → demo-app: 5 pods — 3 Running/Ready, 2 Running/Unready

📋 get_pod_logs(pod_name=demo-app-ddd)
   → [ERROR] PostgreSQL rejected connection 1/10: too many clients
   → [ERROR] Database max_connections limit reached

📋 get_pod_logs(pod_name=postgres-zzz)
   → FATAL: sorry, too many clients already
   → FATAL: sorry, too many clients already

🧠 Agent: Root cause identifiée — PostgreSQL max_connections saturé.
          5 pods × 10 connexions = 50 > max_connections=30.
          La correction doit augmenter max_connections côté PostgreSQL.

📂 read_manifest(path=apps/postgres/k8s/deployment.yaml)
   → args: ["-c", "max_connections=30"]  ← trouvé

🔧 apply_fix(path=apps/postgres/k8s/deployment.yaml, ...)
   → max_connections=30 → max_connections=200
   → ✓ git commit: "fix: increase postgres max_connections to 200"
   → ✓ git push

🔄 check_argocd_sync(app_name=postgres)
   → Synced ✓  (postgres pod redémarre avec la nouvelle config)

⏳ wait_for_healthy(label_selector=app=demo-app)
   → ✓ All 5 pods Running

✓ Incident résolu en ~120s
```

---

## Acte 4 — Guérison

```bash
kubectl get pods -n default
```
```
demo-app-aaa   1/1   Running   0
demo-app-bbb   1/1   Running   0
demo-app-ccc   1/1   Running   0
demo-app-ddd   1/1   Running   0   ← était en erreur
demo-app-eee   1/1   Running   0   ← était en erreur
postgres-zzz   1/1   Running   0   (redémarré avec max_connections=200)
```

**Browser** → tous les refreshes montrent **HEALTHY** · `10 / 10 connections held open`

```bash
# Montrer le commit du fix
git -C ~/code/ia-ops-argo-app log --oneline -3
```
```
x1y2z3a fix: increase postgres max_connections to 200
a4b5c6d scale: increase demo-app to 5 replicas   ← le scale qui a tout déclenché
...
```

> *"L'agent a corrélé les logs applicatifs et les logs postgres, compris que c'est une contrainte infrastructure, modifié la configuration PostgreSQL dans Git. ArgoCD a redémarré postgres avec la nouvelle valeur. Aucune intervention humaine."*

---

## Reset

```bash
~/code/ia-ops-demo-lab/scripts/reset.sh
```

Remet `replicas: 2` et `max_connections=30` dans `ia-ops-argo-app`, force le sync ArgoCD.
