# Runbook: Stage 2 API Dependency Upgrade (2026-04-12)

## Scope

- OpenEats API dependency refresh only.
- OpenEats DB, nginx, web images remain pinned and unchanged.
- No changes to any `tts-*` containers/services.

## Baseline

- Current API image: `adaptiman/openeats-api@sha256:0708a8b232dbd11a720e07bc171b663eb1038cb5ea9249a2c1f695d71c61e8c2`
- Current API runtime: Python 3.6.5, Django 2.1.7, DRF 3.9.1

## Target (Conservative Increment)

Built local image from current API digest with updated backend libraries:
- Django 2.2.28
- djangorestframework 3.9.1 (unchanged for compatibility)
- django-filter 2.1.0 (unchanged)
- django-cors-headers 1.3.1 (unchanged)
- mysqlclient 1.4.6
- Pillow 6.2.2
- requests 2.27.1

Compatibility note:
- DRF 3.10+ introduced code-level incompatibilities (`detail_route`, `base_name`) in this codebase.
- This stage intentionally avoids API code refactors and keeps DRF on 3.9.1.

## Execution Steps

1. Build upgraded API image locally.
2. Validate dependencies in image.
3. Run Django checks and migration plan against production DB from one-off container.
4. Update `docker-prod.version.yml` to upgraded API image.
5. Restart OpenEats API and nginx.
6. Verify OpenEats endpoints and health.

## Rollback

1. Restore API image in `docker-prod.version.yml` to baseline digest.
2. Redeploy API and nginx:

```bash
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d api nginx
```

3. Verify endpoints with `ops/open-eats-health.sh`.

## Note on coverage

- This stage updates backend API libraries only.
- Frontend libraries remain unchanged until Stage 3.
