# Hotfix: Browse 429 Errors and Image Drift (2026-04-12)

## What changed

1. Added nginx proxy headers so API receives real client identity:
- `X-Real-IP`
- `X-Forwarded-For`
- `X-Forwarded-Proto`

Files:
- `ops/nginx/default.conf`
- `docker-prod.override.yml`

2. Pinned production images to immutable digests (no floating `latest` drift).

File:
- `docker-prod.version.yml`

## Why

- Browse page requests were intermittently returning `429` from API endpoints.
- API uses DRF anonymous throttling at `100/hour`.
- Without forwarded client IP headers, all users can appear to come from one proxy source and hit throttling sooner.
- Floating `latest` tags allow unplanned runtime drift.

## Deploy this hotfix

From repo root:

```bash
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml config >/tmp/openeats.compose.rendered.yml

docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d nginx
```

## Verify

```bash
docker logs --tail 200 openeats-nginx-1 | grep ' /api/v1/' | tail -n 20
```

Expected:
- Lower frequency of `429` responses for normal browsing traffic.
- Browse category filters become responsive/stable.

## Rollback (full)

1. Remove nginx mounted override line from `docker-prod.override.yml`:

```yaml
- ./ops/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
```

2. Restore `docker-prod.version.yml` to previous tag form (`:latest`) or your prior committed file.

3. Redeploy previous state:

```bash
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d
```

## Rollback (headers only)

If only the nginx override causes issues:

1. Remove nginx mounted override line from `docker-prod.override.yml`.
2. Restart nginx only:

```bash
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d nginx
```
