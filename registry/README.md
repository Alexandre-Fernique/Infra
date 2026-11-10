# Container registry

Registry privé (CNCF Distribution `registry:3`) derrière Traefik, sur **`localhost:5050`**.
Push **et** pull exigent un login : l'accès anonyme est refusé.

```
docker ──▶ Traefik :5050 ──┬─ /v2/*  ─▶ registry       (vérifie le JWT via config/jwks.json)
                           └─ /auth  ─▶ registry-auth  (docker_auth : login + ACL ─▶ JWT signé)
```

## Utilisateurs et droits

Définis dans [auth/config.yml](auth/config.yml) :

| Utilisateur | Droits               |
|-------------|----------------------|
| `admin`     | push, pull, delete   |
| `ci`        | pull uniquement      |

Les mots de passe générés sont dans `.credentials` (fichier en chmod 600, à ne pas committer).

Ajouter un utilisateur : `htpasswd -nbBC 10 <user> <password>`, copier le hash (la partie
après `:`) dans `users:`, ajouter une règle dans `acl:`, puis `docker compose restart registry-auth`.
Les ACL acceptent des motifs, par ex. `match: { account: "alice", name: "alice/*" }`.

## Utilisation

```bash
docker login localhost:5050 -u admin
docker tag mon-app:1.0 localhost:5050/mon-app:1.0
docker push localhost:5050/mon-app:1.0
docker pull localhost:5050/mon-app:1.0
```

Dans un compose : `image: localhost:5050/mon-app:1.0`.

## Démarrage / clés

```bash
./gen-keys.sh            # 1re fois : clé de signature des tokens + config/jwks.json
docker compose up -d     # après traefik/ et monitoring/
./gen-keys.sh --force && docker compose restart   # rotation de la clé
```

## Sécurité : ce qu'il faut savoir

- Docker contacte `localhost:<port>` d'abord en **HTTPS sans vérifier le certificat** (certificat
  par défaut de Traefik), puis en HTTP. Les échanges avec `/v2` passent donc en TLS non vérifié.
- La récupération du token (`/auth`, qui transporte le mot de passe) se fait en **HTTP clair** :
  Docker exige un certificat valide pour un realm en HTTPS. Sans risque tant que tout reste
  sur `localhost` ; **à ne pas exposer tel quel sur un réseau**.
- Accès depuis une autre machine : définir `REGISTRY_PUBLIC_URL=http://<hôte>:5050`, puis sur
  chaque client ajouter `"insecure-registries": ["<hôte>:5050"]` dans la config du daemon Docker.
  Les mots de passe circuleront alors en clair : prévoir un vrai certificat (Let's Encrypt ou CA
  interne) avant de le faire.
- Les tokens expirent après 15 min (`token.expiration`).

## Observabilité

- Métriques : `registry:5001/metrics` scrapé par Alloy ▶ Prometheus
- Logs : `registry` et `registry-auth` (label `logs.collect=true`) ▶ Loki
- Traces : OTLP ▶ Alloy ▶ Tempo (`service.name=registry`)
- Dashboard Grafana : **Observabilité › Container registry**
