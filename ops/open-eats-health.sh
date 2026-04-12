#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ARGS=(-f docker-prod.yml -f docker-prod.version.yml -f docker-prod.override.yml)

cd "$ROOT_DIR"

echo "== OpenEats Health Snapshot =="
date -u '+UTC: %Y-%m-%d %H:%M:%S'
echo

echo "-- Container Status --"
docker ps --filter name=openeats --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "-- Compose Status --"
docker compose "${COMPOSE_ARGS[@]}" ps
echo

echo "-- Endpoint Checks --"
for url in \
  "https://www.cookbook.thesweeneys.org/browse/" \
  "https://www.cookbook.thesweeneys.org/api/v1/recipe/recipes/?limit=1" \
  "https://www.cookbook.thesweeneys.org/api/v1/recipe_groups/course-count/"
do
  code="$(curl -sk -o /dev/null -w '%{http_code}' "$url" || true)"
  printf '%-90s %s\n' "$url" "$code"
done
echo

echo "-- Recent API Status Mix (nginx access logs) --"
docker logs --tail 800 openeats-nginx-1 2>&1 \
  | grep ' /api/v1/' \
  | awk -F'"' '{print $3}' \
  | awk '{print $1}' \
  | grep -E '^[0-9]{3}$' \
  | sort | uniq -c | sort -nr || true
echo

echo "-- Recent OpenEats Errors (api + nginx) --"
{
  docker logs --tail 120 openeats-api-1 2>&1
  docker logs --tail 120 openeats-nginx-1 2>&1
} | egrep -i 'error|exception|traceback| 5[0-9][0-9] ' | tail -n 40 || true
