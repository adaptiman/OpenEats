# Updating the App

First pull the latest from this repo:
```bash
cd OpenEats
git pull
```

Then check the release notes about any changes to the following files:
- docker-compose.yml
- env_prod.list

There should only be changes to these files in major releases (IE. 2.0.0, 3.0.0)

Once you know your env and docker compose files are up to date, Run:

```bash
./quick-start.py
```
OR
```bash
./quick-start.py --help
```

The quick start script will do a few things.
1. Takes a backup of the database and media.
2. Builds local images from the sibling repos.
3. Restarts OpenEats from `docker-compose.yml`.

Enjoy!
