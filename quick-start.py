#!/usr/bin/env python3
# encoding: utf-8

from pathlib import Path
from subprocess import run, PIPE
from time import sleep, time

COMPOSE_FILE = 'docker-compose.yml'


def run_cmd(cmd, shell=False, check=True):
    """Run a command and optionally capture output."""
    return run(cmd, shell=shell, check=check, stdout=PIPE, stderr=PIPE, text=True)


def container_status(service):
    """Return state/health for a compose service container."""
    container_id = run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'ps', '-q', service])
    cid = container_id.stdout.strip()
    if not cid:
        return 'missing'

    state = run_cmd([
        'docker', 'inspect',
        '--format',
        '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{.State.ExitCode}}',
        cid,
    ])
    parts = state.stdout.strip().split('|')
    status = parts[0] if len(parts) > 0 else 'unknown'
    health = parts[1] if len(parts) > 1 else ''
    exit_code = parts[2] if len(parts) > 2 else ''

    if status == 'exited' and exit_code == '0':
        return 'completed'
    if health:
        return health
    return status


def wait_for_readiness(timeout_seconds=420, interval_seconds=5):
    """Wait until core services are healthy and HTTPS endpoint responds."""
    print("Waiting for services to become ready...")
    deadline = time() + timeout_seconds

    while time() < deadline:
        db = container_status('db')
        api = container_status('api')
        nginx = container_status('nginx')
        web = container_status('web')

        code = run_cmd(
            [
                'curl', '-sk', '-o', '/dev/null', '-w', '%{http_code}',
                'https://www.cookbook.thesweeneys.org/browse/'
            ],
            check=False,
        ).stdout.strip()

        print(f"db={db} api={api} nginx={nginx} web={web} browse={code or 'n/a'}")

        core_ready = db == 'healthy' and api == 'healthy' and nginx in ('healthy', 'running')
        web_ready = web in ('running', 'completed')
        endpoint_ready = code == '200'

        if core_ready and web_ready and endpoint_ready:
            print('OpenEats is ready.')
            return True

        sleep(interval_seconds)

    print('Timed out waiting for full readiness. Use ops/open-eats-health.sh for details.')
    return False


def print_compose_status():
    """Print current compose service status table."""
    print("\nCurrent compose status:")
    status = run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'ps'], check=False)
    print(status.stdout.strip())


def run_health_snapshot():
    """Run health snapshot script if it exists."""
    health_script = Path('ops/open-eats-health.sh')
    if not health_script.exists():
        return

    print("\nRunning health snapshot...")
    result = run_cmd([str(health_script)], check=False)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)


def backup_if_running():
    """Best-effort backup of DB and media before restarting services."""
    print("================")
    print("Saving Backups")
    print("================")

    db = run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'ps', '-q', 'db'])
    db_container = db.stdout.strip()
    if db_container:
        print("Taking database backup (openeats.sql)...")
        run_cmd(
            (
                "docker exec {db} sh -lc 'DB_NAME=\"${{MYSQL_DATABASE:-openeats}}\"; "
                "if command -v mariadb-dump >/dev/null 2>&1; then "
                "  exec mariadb-dump \"$DB_NAME\" -uroot -p\"$MYSQL_ROOT_PASSWORD\"; "
                "else "
                "  exec mysqldump \"$DB_NAME\" -uroot -p\"$MYSQL_ROOT_PASSWORD\"; "
                "fi' > openeats.sql"
            ).format(db=db_container),
            shell=True,
        )

    api = run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'ps', '-q', 'api'])
    api_container = api.stdout.strip()
    if api_container:
        print("Taking media backup (site-media/)...")
        target = str(Path.cwd() / 'site-media')
        run_cmd(['docker', 'cp', f'{api_container}:/code/site-media/.', target], check=False)


def start_containers(build=True):
    """Start the OpenEats stack from local sources."""
    print("==================")
    print("Starting OpenEats")
    print("==================")

    run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'up', '-d', 'db'])

    if build:
        print("Building local images from sibling repositories...")
        run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'build', 'api', 'web', 'nginx'])

    run_cmd(['docker', 'compose', '-f', COMPOSE_FILE, 'up', '-d', 'api', 'web', 'nginx'])

    print("App started. The web build container may take a bit to finish generating UI assets.")
    ready = wait_for_readiness()
    print_compose_status()
    if not ready:
        print("\nStartup timed out before full readiness.")
    run_health_snapshot()


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(
        description='OpenEats quick setup script. '
                    'This script will restart your OpenEats server and '
                    'take a database and recipe image backup before startup.'
    )
    parser.add_argument(
        '--no-build',
        action='store_true',
        help='Skip local docker build and restart using existing local images.'
    )
    args = parser.parse_args()

    backup_if_running()
    start_containers(build=not args.no_build)
