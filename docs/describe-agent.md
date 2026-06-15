⏺ Voici une analyse pédagogique des deux fichiers, concept par concept, avec les lignes exactes à regarder.

  ---
  1. Le System Prompt — définir le rôle et les règles
  
  main.py:26-75

  SYSTEM_PROMPT = """\
  You are an elite SRE (Site Reliability Engineer) AI agent...

  C'est la mémoire permanente de l'agent — tout ce qui ne change jamais entre les tours. Il contient :
  - Le rôle ("tu es un SRE expert")
  - Les contraintes ("jamais kubectl apply direct, toujours GitOps")
  - Le contexte du système (structure des fichiers, formule des connexions 5×10>30)
  - Le workflow attendu (étapes 1 à 7 explicites)

  Ce qu'il faut comprendre : le LLM n'a aucune connaissance de ton cluster. Tout ce qu'il sait sur ton système vient de là. Si tu
  supprimes la section "Architecture: DB Connections", l'agent ne pourra plus corréler le scaling avec l'épuisement des connexions.

  ---
  2. La boucle agentique — le cœur du système

  main.py:155-248

  while iteration < max_iterations:          # ligne 156
      iteration += 1
      # ... appel LLM avec streaming ...
      if stop_reason == "end_turn" and not tool_calls:
          break                              # ligne 247

  C'est la boucle agentique. À chaque tour :
  1. Le LLM reçoit tout l'historique
  2. Il répond (texte + éventuellement des appels d'outils)
  3. Les outils sont exécutés
  4. Les résultats sont ajoutés à l'historique
  5. On recommence

  L'agent s'arrête quand stop_reason == "end_turn" et qu'il n'y a plus d'outils à exécuter. C'est l'API Anthropic qui indique end_turn
  quand le modèle estime avoir terminé.

  max_iterations = 12 (ligne 153) est le garde-fou — sans ça, un bug dans un outil pourrait faire tourner l'agent indéfiniment.

  ---
  3. Le contexte — la mémoire de session

  main.py:161, 241-245

  messages = []                              # ligne 161 — vide au départ

  # À chaque tour, on accumule :
  messages.append({"role": "assistant", "content": assistant_content})   # 241
  messages.append({"role": "user",      "content": tool_results})        # 244

  messages est toute la mémoire de l'agent pour cet incident. Il grandit à chaque tour. Au tour 5, le LLM voit les résultats des tours 1,
  2, 3, 4 et peut raisonner dessus.

  Conséquence critique : quand l'agent corrèle les logs de demo-app-ddd avec les logs de PostgreSQL pour diagnostiquer "too many clients",
   c'est possible uniquement parce que ces deux résultats sont dans messages en même temps. Sans ce contexte cumulé, l'agent ne peut pas
  raisonner entre plusieurs observations.

  Limite : cette mémoire disparaît à la fin de run_agent(). L'agent ne se souvient pas des incidents précédents. C'est une mémoire de
  session, pas de long terme.

  ---
  4. La définition des outils — le contrat LLM ↔ code
  
  tools.py:14-151

  TOOLS = [
      {
          "name": "get_pod_logs",
          "description": "Get recent logs from a specific pod...",   # ← ce que le LLM lit
          "input_schema": {
              "type": "object",
              "properties": {
                  "pod_name": {"type": "string", "description": "Full name of the pod"},
                  "previous": {"type": "boolean", "default": True},
              },
              "required": ["pod_name"],
          },
      },

  La description est le seul moyen qu'a le LLM de savoir quand appeler cet outil. Change "Get recent logs" en "Get historical audit logs"
  et l'agent l'utilisera moins pour diagnostiquer des crashs en temps réel. La qualité des descriptions est aussi importante que le code
  de l'outil lui-même.

  required: ["pod_name"] dit au LLM quels paramètres il doit fournir. Les autres (previous, lines) ont des defaults — le LLM peut les
  omettre ou les préciser selon le contexte.

  ---
  5. Le Tool Calling — comment le LLM "agit"
  
  main.py:174-209 (parsing du stream) + main.py:222-245 (exécution)

  # Le LLM produit un bloc "tool_use" dans le stream
  elif block.type == "tool_use":
      current_tool = {"id": block.id, "name": block.name, "input": {}}

  # L'input JSON arrive par morceaux (streaming)
  elif delta.type == "input_json_delta":
      current_input_json += delta.partial_json

  # On exécute l'outil avec les paramètres parsés
  result = execute_tool(tool_call["name"], tool_call["input"])   # ligne 232

  # On renvoie le résultat au LLM comme "user" message
  tool_results.append({
      "type": "tool_result",
      "tool_use_id": tool_call["id"],    # ← lie le résultat à l'appel
      "content": result,
  })

  Le LLM ne "fait" rien lui-même — il émet des intentions structurées ({"name": "get_pod_logs", "input": {"pod_name": "demo-app-xxx"}}).
  C'est ton code qui exécute la vraie commande kubectl et renvoie le résultat. Le LLM voit ensuite ce résultat et décide quoi faire
  ensuite.

  tool_use_id est important : il lie chaque résultat à l'appel qui l'a produit, permettant au LLM de savoir quel outil a retourné quoi,
  même si plusieurs outils sont appelés dans le même tour.

  ---
  6. L'implémentation des outils — le pont vers le monde réel

  tools.py:172-243

  def get_cluster_status(namespace: str = "default") -> str:
      pods = _run(["kubectl", "get", "pods", "-n", namespace, "-o", "wide"])
      deploys = _run(["kubectl", "get", "deployments", "-n", namespace])
      return f"=== PODS ===\n{pods}\n\n=== DEPLOYMENTS ===\n{deploys}"

  def apply_fix(path: str, content: str, commit_message: str) -> str:
      full_path = Path(REPO_PATH) / path
      full_path.write_text(content)
      git_add    = _run(["git", "-C", REPO_PATH, "add", path])
      git_commit = _run(["git", "-C", REPO_PATH, "commit", "-m", commit_message])
      git_push   = _run(["git", "-C", REPO_PATH, "push"], timeout=15)
      return f"✓ File written\n✓ Git add: {git_add}\n..."

  Tous les outils retournent des strings. Le LLM ne reçoit que du texte — il ne peut pas manipuler d'objets Python, d'objets Kubernetes,
  etc. Donc get_cluster_status formate le résultat de kubectl en texte lisible, et apply_fix effectue 3 opérations Git réelles (write +
  commit + push) en une seule invocation.

  Ce que ça révèle sur la conception : un outil = une unité d'action atomique du point de vue du LLM. apply_fix aurait pu être 3 outils
  séparés (write_file, git_commit, git_push), mais regrouper les 3 réduit le nombre de tours de boucle nécessaires et rend le scénario
  GitOps non-contournable (le LLM ne peut pas écrire un fichier sans commiter).

  ---
  7. Le streaming — voir l'agent "penser"
  
  main.py:165-209

  with client.messages.stream(...) as stream:
      for event in stream:
          if delta.type == "text_delta":
              console.print(delta.text, end="")   # affiche token par token

  Le streaming fait deux choses : il rend la démo visuelle (on voit l'agent raisonner en direct), et il permet de traiter les outils dès
  que leur input JSON est complet — sans attendre la fin du message entier.

  ---
  8. Ce qui manque — les limites de cet agent

  C'est aussi instructif que ce qui est présent :

  ┌───────────────────────────┬───────────┬────────────────────────────────────────────────────────────┐
  │          Concept          │ Présent ? │                           Impact                           │
  ├───────────────────────────┼───────────┼────────────────────────────────────────────────────────────┤
  │ Mémoire long terme        │ ✗         │ L'agent oublie tout entre deux python main.py              │
  ├───────────────────────────┼───────────┼────────────────────────────────────────────────────────────┤
  │ Outils en parallèle       │ ✗         │ Il appelle les outils un par un, séquentiellement          │
  ├───────────────────────────┼───────────┼────────────────────────────────────────────────────────────┤
  │ Déclenchement automatique │ ✗         │ Il faut lancer manuellement python main.py                 │
  ├───────────────────────────┼───────────┼────────────────────────────────────────────────────────────┤
  │ Rollback sur échec        │ ✗         │ Si le fix aggrave les choses, il ne revient pas en arrière │
  ├───────────────────────────┼───────────┼────────────────────────────────────────────────────────────┤
  │ Apprentissage             │ ✗         │ Il ne mémorise pas les patterns d'incidents résolus        │
  └───────────────────────────┴───────────┴────────────────────────────────────────────────────────────┘