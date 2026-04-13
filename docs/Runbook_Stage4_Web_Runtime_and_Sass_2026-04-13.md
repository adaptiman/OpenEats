# Runbook: Stage 4 Web Runtime + Sass Modernization (2026-04-13)

## Scope

- Upgrade OpenEats web build runtime from Node 14 to Node 16.
- Keep behavior identical for API routing, auth, and UI features.
- Migrate web Sass toolchain from `node-sass` to `sass` (dart-sass).
- No changes to any `tts-*` containers/services.

## Baseline

- Web image: `adaptiman/openeats-web:stage4-20260412`
- Web Docker base: `node:14.21.3-alpine`
- Sass stack: `node-sass` + `sass-loader`

## Target

- Web image: `adaptiman/openeats-web:stage5-20260413`
- Web Docker base: `node:16.20.2-alpine`
- Sass stack: `sass==1.32.13` + `sass-loader==7.3.1`

## Execution Steps

1. Build and validate web image locally:

```bash
docker build --no-cache -t adaptiman/openeats-web:stage5-20260413 /home/adaptiman/openeats-web

docker run --rm adaptiman/openeats-web:stage5-20260413 sh -lc 'set -e; node -v; yarn -v; CI=true yarn test --watch=false; yarn build'
```

2. Update selector in `docker-prod.version.yml`:

```yaml
services:
  web:
    image: adaptiman/openeats-web:stage5-20260413
```

3. Redeploy only affected services:

```bash
cd /home/adaptiman/OpenEats
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d web nginx
```

4. Wait for one-shot web build completion:

```bash
docker wait openeats-web-1
docker logs --tail 80 openeats-web-1
```

5. Verify production endpoints:

```bash
curl -sk -o /dev/null -w 'browse=%{http_code}\n' https://www.cookbook.thesweeneys.org/browse/
curl -sk -o /dev/null -w 'recipes=%{http_code}\n' 'https://www.cookbook.thesweeneys.org/api/v1/recipe/recipes/?limit=1'
curl -sk -o /dev/null -w 'course=%{http_code}\n' 'https://www.cookbook.thesweeneys.org/api/v1/recipe_groups/course-count/'
```

## Rollback

1. Revert web image selector in `docker-prod.version.yml` to prior known-good tag (`stage4-20260412`).
2. Redeploy web + nginx:

```bash
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d web nginx
```

3. Recheck endpoints and logs.

## Notes

- With one-shot web builds, `/browse` can return `500` briefly during startup until `public-ui/index.html` exists.
- Keep retries in endpoint checks during deployment windows.
