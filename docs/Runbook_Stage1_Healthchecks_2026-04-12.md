# Runbook: Stage 1 Healthchecks and Observability (2026-04-12)

## Scope

- OpenEats only.
- No changes to any `tts-*` services.

## Changes

1. Added container healthchecks:
- `api` healthcheck probes local API endpoint.
- `nginx` healthcheck probes local root path.

File:
- `docker-prod.yml`

2. Added a health snapshot script:
- `ops/open-eats-health.sh`

## Deploy

```bash
cd /home/adaptiman/OpenEats
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml config >/tmp/openeats.stage1.config.yml
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d
```

## Verify

```bash
./ops/open-eats-health.sh
```

Expected:
- `openeats-db-1` healthy
- `openeats-api-1` healthy after start period
- `openeats-nginx-1` healthy after start period
- Browse and API endpoints return HTTP 200

## Rollback

1. Revert `docker-prod.yml` healthcheck blocks for `api` and `nginx`.
2. Redeploy:

```bash
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d
```

3. Optionally remove script:
- `ops/open-eats-health.sh`
