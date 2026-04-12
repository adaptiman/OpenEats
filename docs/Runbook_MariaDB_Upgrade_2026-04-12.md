# Runbook: OpenEats MariaDB Upgrade to Current Image (2026-04-12)

## Scope and Safety

- Scope: OpenEats only (`openeats-*` containers and volumes).
- Excluded: `tts-conductor` and any `tts-*` containers/services.
- Strategy: Logical migration to a new volume and side-by-side validation, then controlled cutover.

## Current Baseline

- Source DB image: `mariadb:5.5.64`
- Source DB container: `openeats-db-1`
- Source DB volume: `openeats_database`
- Source schema: `openeats` (InnoDB tables)

## Target

- Target DB image: `mariadb:latest` (resolved to immutable digest during execution)
- Target volume: `openeats_database_current`
- Charset/collation/sql_mode preserved to reduce app behavior change:
  - `--character-set-server=latin1`
  - `--collation-server=latin1_swedish_ci`
  - `--sql-mode=`

## Stage 1: Backup and Snapshot (No downtime)

1. Create timestamped backup folder under `backups/`.
2. Logical dump of `openeats` schema from current prod DB.
3. Volume backup archive of `openeats_database` as a secondary fallback.
4. Record checksums and baseline DB metadata.

Fallback:
- No production service changes yet. Continue running current stack.

## Stage 2: Side-by-side Restore and Validation (No downtime)

1. Create target volume `openeats_database_current`.
2. Start temporary target DB container (`openeats-db-next`) on `openeats_default` network.
3. Restore logical dump into target DB.
4. Validate target DB responds and table counts/metadata look correct.

Fallback:
- Remove temporary container and target volume. Production remains unchanged.

## Stage 3: Cutover (Short maintenance window)

1. Update compose DB service to target image and target volume.
2. Stop OpenEats app writers/readers (`nginx`, `api`, `web`) and old `db`.
3. Start upgraded `db` via compose.
4. Start `api`, `web`, `nginx` via compose.
5. Verify key endpoints and container health.

Important for current MariaDB image:
- Use `mariadb-admin` for healthcheck (not `mysqladmin`).
- Compose healthcheck should be:
  - `test: ["CMD", "mariadb-admin", "ping", "-h", "localhost"]`

Fallback:
1. Revert compose DB config to old image/volume.
2. Restart OpenEats services.
3. Validate endpoints.

## Stage 4: Hold and Post-checks

- Keep old volume `openeats_database` intact for rollback.
- Keep logical and volume backups.
- Monitor logs and API status mix.

## Quick Rollback Commands

```bash
# Revert DB image/volume in docker-prod.yml to source settings,
# then restart OpenEats services:

docker compose -f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml up -d db api web nginx
```

## Execution Log

This runbook is paired with terminal execution in this maintenance session.

Result in this session:
- Source `5.5.64` migrated to target `12.2.2` on new volume.
- Source/target table and key row counts matched (`auth_user`, `recipe_recipe`).
- OpenEats endpoints returned 200 after cutover and service warm-up.
