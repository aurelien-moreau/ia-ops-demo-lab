# Scénario A — Mauvaise configuration DATABASE_URL

> *Un développeur pousse une `DATABASE_URL` corrompue en production. L'app perd l'accès à la base. L'agent IA détecte, corrige et confirme la guérison — sans intervention humaine.*

---

## Concept

```
Mauvaise config poussée dans Git
         │
         ▼
ArgoCD sync → ConfigMap mis à jour
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
Agent IA → lit les logs → lit le ConfigMap → corrige → push
         │
         ▼
ArgoCD sync → Reloader restart → App HEALTHY ✓
```

---

## Architecture concernée

```
ia-ops-argo-app/
└── apps/demo-app/k8s/
    └── configmap.yaml    ← LE FICHIER QU'ON MODIFIE
```

L'app lit `DATABASE_URL` depuis le ConfigMap au démarrage.
Si l'URL est malformée, elle log une erreur et la page passe en rouge.

---

## Acte 1 — Montrer l'état sain

```bash
kubectl get pods -n default
```
```
demo-app-xxx   1/1   Running   0
demo-app-yyy   1/1   Running   0
postgres-zzz   1/1   Running   0
```

**Browser** → http://localhost:8081 → **HEALTHY** (vert)
**ArgoCD** → https://localhost:8080 → toutes les apps en vert

> *"Voilà notre stack : deux replicas de l'app, une base PostgreSQL, tout géré par ArgoCD depuis GitHub."*

Chaque refresh montre un pod différent (round-robin).

---

## Acte 2 — Introduire le bug

Ouvrir `~/code/ia-ops-argo-app/apps/demo-app/k8s/configmap.yaml` :

```yaml
# Avant (sain)
DATABASE_URL: "postgres://app:s3cr3t@postgres.default.svc.cluster.local:5432/appdb?sslmode=disable"

# Après (cassé) — supprimer tout sauf le préfixe
DATABASE_URL: "postgres://"
```

Commiter et pousser :

```bash
cd ~/code/ia-ops-argo-app
git add apps/demo-app/k8s/configmap.yaml
git commit -m "fix: update database endpoint configuration"
git push
```

> *"Un développeur vient de pousser une mauvaise config en production. Ça arrive."*

**Timings après le push :**

| Délai | Événement |
|-------|-----------|
| ~10s | ArgoCD → **OutOfSync** → **Synced** |
| ~15s | Reloader détecte le ConfigMap modifié → rolling restart |
| ~20s | Nouveaux pods démarrent avec `DATABASE_URL: "postgres://"` |
| ~25s | Browser → page **DÉGRADÉE** (rouge, pulsante) |
| ~25s | ArgoCD UI → app en état **Degraded** |

**Montrer les logs :**

```bash
kubectl logs -l app=demo-app -n default --prefix=true --tail=5
```
```
[demo-app-xxx] [ERROR] DATABASE_URL is invalid: 'postgres://'
[demo-app-xxx] [ERROR] Expected: postgres://user:password@host:port/dbname?sslmode=disable
[demo-app-yyy] [ERROR] DATABASE_URL is invalid: 'postgres://'
```

---

## Acte 3 — Lancer l'agent IA

Dans un nouveau terminal :

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

🧠 Agent: Je vais inspecter l'état du cluster...

🔍 get_cluster_status(namespace=default)
   → demo-app pods: Running (Unready)

📋 get_pod_logs(pod_name=demo-app-xxx)
   → [ERROR] DATABASE_URL is invalid: 'postgres://'

📂 read_manifest(path=apps/demo-app/k8s/configmap.yaml)
   → DATABASE_URL: "postgres://"  ← trouvé

🧠 Agent: Root cause identifiée — DATABASE_URL malformée.
          La valeur 'postgres://' est incomplète.
          Correction en cours...

🔧 apply_fix(path=apps/demo-app/k8s/configmap.yaml, ...)
   → ✓ File written
   → ✓ git commit: "fix: restore valid DATABASE_URL"
   → ✓ git push

🔄 check_argocd_sync(app_name=demo-app)
   → Synced ✓

⏳ wait_for_healthy(label_selector=app=demo-app)
   → ✓ All pods Running

✓ Incident résolu en ~90s
```

---

## Acte 4 — Guérison

**Browser** → http://localhost:8081 → **HEALTHY** (vert)
**ArgoCD** → retour en **Healthy**

```bash
# Montrer le commit du fix dans Git
git -C ~/code/ia-ops-argo-app log --oneline -3
```
```
a1b2c3d fix: restore valid DATABASE_URL
f4e5d6c fix: update database endpoint configuration  ← le bug
...
```

> *"Le fix est dans Git. La piste d'audit est complète. Aucun humain n'a été réveillé à 3h du matin."*

---

## Reset

```bash
~/code/ia-ops-demo-lab/scripts/reset.sh
```
