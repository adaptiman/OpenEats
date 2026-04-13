# Runbook: Restore OpenEats From Backup (2026-04-13)

This runbook restores OpenEats using backups created by:

- `/home/adaptiman/OpenEats/ops/local/backup-openeats.sh`

Expected backup location format:

- `/home/adaptiman/thesweeneyscookbooksa/openeats-backups/<timestamp>/`

## What the backup contains

- `db/openeats.sql` (logical database dump)
- `site-media/` (media files copied from API container)
- `volumes/*.tar.gz` (named volume archives)
- `config/*` (compose and env snapshots)
- `host/dhparam-2048.pem` and `host/docker-volumes.tar.gz` (TLS/certbot host data)
- `meta/*` and `checksums/SHA256SUMS.txt`

## Prerequisites

- Docker and Docker Compose installed
- OpenEats repo available at `/home/adaptiman/OpenEats`
- Backup mount available at `/home/adaptiman/thesweeneyscookbooksa`
- Correct file permissions to write `/docker-volumes` and Docker volumes

## 1. Choose backup set and verify integrity

```bash
BACKUP_ROOT=$(ls -1dt /home/adaptiman/thesweeneyscookbooksa/openeats-backups/* | head -n1)
echo "$BACKUP_ROOT"

cd "$BACKUP_ROOT"
sha256sum -c checksums/SHA256SUMS.txt
```

Expected: all lines show `OK`.

## 2. Stop OpenEats services

```bash
cd /home/adaptiman/OpenEats
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml down
```

## 3. Restore config snapshot (compose/env files)

```bash
cd /home/adaptiman/OpenEats
cp -a "$BACKUP_ROOT/config/docker-prod.yml" ./
cp -a "$BACKUP_ROOT/config/docker-prod.version.yml" ./
cp -a "$BACKUP_ROOT/config/docker-prod.override.yml" ./
cp -a "$BACKUP_ROOT/config/env_prod.list" ./
cp -a "$BACKUP_ROOT/config/env_stg.list" ./ 2>/dev/null || true
cp -a "$BACKUP_ROOT/config/env_dev.list" ./ 2>/dev/null || true
```

## 4. Restore TLS host data (if needed)

Only do this if TLS/certbot data is missing or corrupted.

```bash
sudo tar -xzf "$BACKUP_ROOT/host/docker-volumes.tar.gz" -C /
sudo cp -a "$BACKUP_ROOT/host/dhparam-2048.pem" /etc/ssl/certs/dhparam-2048.pem
```

## 5. Restore named volumes from archives

```bash
for vol in openeats_database_current openeats_site-media openeats_static-files openeats_public-ui; do
  docker volume create "$vol" >/dev/null
  docker run --rm \
    -v "$vol:/volume" \
    -v "$BACKUP_ROOT/volumes:/backup:ro" \
    alpine sh -lc "cd /volume && rm -rf ./* && tar -xzf /backup/${vol}.tar.gz"
done
```

## 6. Start DB and import SQL dump

Even with a restored DB volume, importing SQL ensures logical consistency from backup.

```bash
cd /home/adaptiman/OpenEats
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d db

# Wait until DB is healthy
until docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml ps | grep -q "openeats-db-1.*healthy"; do
  echo "Waiting for db..."
  sleep 2
done

# Import dump
cat "$BACKUP_ROOT/db/openeats.sql" | docker exec -i openeats-db-1 mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" openeats
```

If `MYSQL_ROOT_PASSWORD` is not exported in shell, source env first:

```bash
cd /home/adaptiman/OpenEats
set -a
source env_prod.list
set +a
```

Then rerun the import command.

## 7. Start full stack

```bash
cd /home/adaptiman/OpenEats
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d
```

## 8. Post-restore validation

```bash
# Service status
cd /home/adaptiman/OpenEats
docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml ps

# Core endpoints
curl -sk -o /dev/null -w 'browse=%{http_code}\n' 'https://www.cookbook.thesweeneys.org/browse/'
curl -sk -o /dev/null -w 'api=%{http_code}\n' 'https://www.cookbook.thesweeneys.org/api/v1/recipe/recipes/?limit=1'
curl -sk -o /dev/null -w 'course-count=%{http_code}\n' 'https://www.cookbook.thesweeneys.org/api/v1/recipe_groups/course-count/'
```

Expected: HTTP `200` for all checks.

## 9. Optional: media/thumbnail spot check

```bash
curl -sk -o /dev/null -w 'thumb=%{http_code}\n' 'https://www.cookbook.thesweeneys.org/site-media/CACHE/images/upload/recipe_photos/baked-egg-avocado-bacon-1440x810/ea23da33ebdc427c10b8531f00787d3a.jpg'
```

Expected: `thumb=200`.
