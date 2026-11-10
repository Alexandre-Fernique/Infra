# Monitoring

```
Traefik / apps ──OTLP──▶ Alloy ──┬─ métriques ─▶ Prometheus ◀─┐ span metrics / service graph
conteneurs (stdout) ────▶  :4317 ├─ logs ───────▶ Loki        │
                           :4318 └─ traces ─────▶ Tempo ──────┘
                                       tout est visualisé dans Grafana (http://grafana.localhost)
```

Corrélations configurées dans Grafana :
- **log → trace** : bouton « Voir la trace » sur un log portant un `trace_id`
- **trace → logs** : depuis une trace, logs Loki ayant le même `trace_id`
- **trace → métriques** : taux de requêtes / latence p95 du service (générées par Tempo)
- **métrique → trace** : exemplars sur les graphes Prometheus (si l'app en émet)

## Démarrage

```bash
cd traefik    && docker compose up -d   # crée le réseau "proxy"
cd monitoring && cp .env.example .env && docker compose up -d
```

Grafana : http://grafana.localhost (identifiants dans `.env`, `admin/admin` par défaut)
→ dossier **Observabilité** › dashboard **Traefik**.

## Brancher une nouvelle app (front / back)

1. Rattacher le service au réseau `proxy` (`networks: proxy: external: true`).
2. **Méthode recommandée — OTLP** : instrumenter l'app avec le SDK OpenTelemetry et définir :
   ```yaml
   environment:
     OTEL_SERVICE_NAME: mon-back
     OTEL_EXPORTER_OTLP_ENDPOINT: http://alloy:4318   # ou :4317 en gRPC
     OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
   ```
   - Métriques → Prometheus, avec `job="mon-back"`
   - Logs → Loki, avec `service_name="mon-back"`
   - Traces → Tempo. Traefik propage l'en-tête `traceparent` (W3C) : les spans du back
     s'accrochent automatiquement à la trace démarrée par Traefik.
3. **Méthode simple — logs stdout** : ajouter le label `logs.collect=true` au conteneur ;
   Alloy lit ses logs Docker et les envoie dans Loki (`service_name` = nom du service compose).

Pour le front (navigateur), l'OTLP/HTTP accepte le CORS depuis `*.localhost` ; il faudra exposer
le port 4318 d'Alloy via Traefik (ex. `otel.localhost`) pour qu'il soit joignable depuis le navigateur.

## Rétention

- Prometheus : 15 jours (`--storage.tsdb.retention.time`)
- Loki : 7 jours (`limits_config.retention_period`)
- Tempo : 7 jours (`compactor.compaction.block_retention`)

Traefik trace 100 % des requêtes (`tracing.sampleRate: 1.0`) : à réduire en production.
